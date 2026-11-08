// Run from this folder:  npm install  &&  npm test
// (needs Java + firebase-tools; see SETUP guide). NOT yet executed by the author.
const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, serverTimestamp } = require('firebase/firestore');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'bloodconnect-test',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/receiver1'), { role: 'receiver', isActive: true, phone: '111' });
    await setDoc(doc(db, 'users/donor1'), { role: 'donor', isActive: true, phone: '222' });
    await setDoc(doc(db, 'donor_profiles/donor1'), {
      userId: 'donor1', bloodGroup: 'O+', city: 'Lahore', donorAvailable: true, isActive: true,
    });
    await setDoc(doc(db, 'donor_profiles/donor2'), {
      userId: 'donor2', bloodGroup: 'O+', city: 'Lahore', donorAvailable: true, isActive: true,
    });
    await setDoc(doc(db, 'blood_requests/req1'), {
      requesterId: 'receiver1', bloodGroup: 'O+', unitsRequired: 1, status: 'pending',
    });
  });
});

const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();
const invite = (donorId) => ({
  bloodRequestId: 'req1', donorId, requesterId: 'receiver1', status: 'pending',
});

test('user cannot read another user (private phone)', async () => {
  await assertFails(getDoc(doc(as('donor1'), 'users/receiver1')));
  await assertSucceeds(getDoc(doc(as('receiver1'), 'users/receiver1')));
});

test('user cannot make themselves admin or change role', async () => {
  await assertFails(updateDoc(doc(as('donor1'), 'users/donor1'), { role: 'admin' }));
  await assertFails(setDoc(doc(as('newuser'), 'users/newuser'), { role: 'admin', isActive: true }));
  await assertSucceeds(setDoc(doc(as('newuser'), 'users/newuser'), { role: 'donor', isActive: true }));
});

test('donor_profiles: signed-in read ok, anonymous denied, no phone on create', async () => {
  await assertSucceeds(getDoc(doc(as('receiver1'), 'donor_profiles/donor1')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'donor_profiles/donor1')));
  await assertFails(setDoc(doc(as('donor3'), 'donor_profiles/donor3'), {
    userId: 'donor3', bloodGroup: 'A+', isActive: true, phone: '333',
  }));
});

test('receiver can create own request, not for someone else', async () => {
  const data = { bloodGroup: 'A+', unitsRequired: 2, status: 'pending' };
  await assertSucceeds(setDoc(doc(as('receiver1'), 'blood_requests/r2'), { ...data, requesterId: 'receiver1' }));
  await assertFails(setDoc(doc(as('receiver1'), 'blood_requests/r3'), { ...data, requesterId: 'someoneElse' }));
});

test('owner can invite a donor once; non-owner cannot', async () => {
  await assertSucceeds(setDoc(doc(as('receiver1'), 'donor_requests/req1_donor1'), invite('donor1')));
  await assertFails(setDoc(doc(as('donor2'), 'donor_requests/req1_donor2'),
    { ...invite('donor2'), requesterId: 'donor2' }));
});

test('invitation to an unavailable donor is denied', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    updateDoc(doc(ctx.firestore(), 'donor_profiles/donor2'), { donorAvailable: false }));
  await assertFails(setDoc(doc(as('receiver1'), 'donor_requests/req1_donor2'), invite('donor2')));
});

test('only the invited donor can read/respond; others cannot', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), invite('donor1')));
  await assertSucceeds(getDoc(doc(as('donor1'), 'donor_requests/req1_donor1')));
  await assertSucceeds(getDoc(doc(as('receiver1'), 'donor_requests/req1_donor1')));
  await assertFails(getDoc(doc(as('donor2'), 'donor_requests/req1_donor1')));
  await assertFails(updateDoc(doc(as('donor2'), 'donor_requests/req1_donor1'), { status: 'accepted' }));
  await assertFails(updateDoc(doc(as('receiver1'), 'donor_requests/req1_donor1'), { status: 'accepted' }));
  await assertSucceeds(updateDoc(doc(as('donor1'), 'donor_requests/req1_donor1'), { status: 'rejected' }));
});

test('donor accept assigns the request; second donor cannot also accept', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), invite('donor1'));
    await setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor2'), invite('donor2'));
  });
  await assertSucceeds(updateDoc(doc(as('donor1'), 'blood_requests/req1'),
    { status: 'accepted', acceptedDonorId: 'donor1', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('donor2'), 'blood_requests/req1'),
    { status: 'accepted', acceptedDonorId: 'donor2', updatedAt: serverTimestamp() }));
});

test('donor cannot accept as someone else or without an invitation', async () => {
  await assertFails(updateDoc(doc(as('donor2'), 'blood_requests/req1'),
    { status: 'accepted', acceptedDonorId: 'donor2', updatedAt: serverTimestamp() }));
});

test('invalid transition: rejected -> accepted is denied', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), { ...invite('donor1'), status: 'rejected' }));
  await assertFails(updateDoc(doc(as('donor1'), 'donor_requests/req1_donor1'), { status: 'accepted' }));
});

test('reports: users can file, cannot read; admin claim can read', async () => {
  const report = { reporterId: 'donor1', reportedUserId: 'receiver1', reason: 'spam', status: 'open' };
  await assertSucceeds(setDoc(doc(as('donor1'), 'reports/rep1'), report));
  await assertFails(getDoc(doc(as('donor1'), 'reports/rep1')));
  await assertSucceeds(getDoc(doc(as('adminUid', { admin: true }), 'reports/rep1')));
});

test('accept shares phone numbers; forged phone numbers are denied', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), invite('donor1'));
    await setDoc(doc(ctx.firestore(), 'blood_requests/req1'), {
      requesterId: 'receiver1', bloodGroup: 'O+', unitsRequired: 1, status: 'pending', requesterPhone: '+92300',
    });
  });
  await assertFails(updateDoc(doc(as('donor1'), 'donor_requests/req1_donor1'),
    { status: 'accepted', donorPhone: '999', requesterPhone: '+92300' }));
  await assertSucceeds(updateDoc(doc(as('donor1'), 'donor_requests/req1_donor1'),
    { status: 'accepted', donorPhone: '222', requesterPhone: '+92300' }));
});

test('blocked requester cannot invite the donor who blocked them', async () => {
  await assertSucceeds(setDoc(doc(as('donor1'), 'users/donor1/blocked/receiver1'), { name: 'R' }));
  await assertFails(setDoc(doc(as('receiver1'), 'donor_requests/req1_donor1'), invite('donor1')));
  await assertFails(getDoc(doc(as('receiver1'), 'users/donor1/blocked/receiver1')));
});

test('fcm tokens are private to their owner', async () => {
  await assertSucceeds(setDoc(doc(as('donor1'), 'users/donor1/fcm_tokens/tok1'), { platform: 'android' }));
  await assertFails(getDoc(doc(as('receiver1'), 'users/donor1/fcm_tokens/tok1')));
});

test('admin audit log: admin appends, others cannot, nobody edits', async () => {
  const admin = as('adminUid', { admin: true });
  await assertSucceeds(setDoc(doc(admin, 'admin_audit/a1'), { action: 'suspend', adminUid: 'adminUid' }));
  await assertFails(setDoc(doc(admin, 'admin_audit/a2'), { action: 'suspend', adminUid: 'someoneElse' }));
  await assertFails(setDoc(doc(as('donor1'), 'admin_audit/a3'), { action: 'x', adminUid: 'donor1' }));
  await assertSucceeds(getDoc(doc(admin, 'admin_audit/a1')));
  await assertFails(getDoc(doc(as('donor1'), 'admin_audit/a1')));
  await assertFails(updateDoc(doc(admin, 'admin_audit/a1'), { action: 'edited' }));
});

test('suspension (free plan): admin suspends, suspended user is blocked from writing', async () => {
  await assertFails(setDoc(doc(as('receiver1'), 'suspended_users/receiver1'), { reason: 'x' }));
  await assertSucceeds(setDoc(doc(as('adminUid', { admin: true }), 'suspended_users/receiver1'), { reason: 'spam' }));
  await assertSucceeds(getDoc(doc(as('receiver1'), 'suspended_users/receiver1')));
  await assertFails(getDoc(doc(as('donor1'), 'suspended_users/receiver1')));
  await assertFails(setDoc(doc(as('receiver1'), 'blood_requests/r9'),
    { requesterId: 'receiver1', bloodGroup: 'A+', unitsRequired: 1, status: 'pending' }));
  await assertFails(setDoc(doc(as('receiver1'), 'donor_requests/req1_donor1'), invite('donor1')));
});

test('admin can mark a user inactive and hide the donor profile', async () => {
  const admin = as('adminUid', { admin: true });
  await assertSucceeds(updateDoc(doc(admin, 'users/donor1'), { isActive: false }));
  await assertSucceeds(updateDoc(doc(admin, 'donor_profiles/donor1'), { isActive: false }));
  await assertFails(updateDoc(doc(as('donor1'), 'users/donor1'), { isActive: true }));
});

test('donor can share and remove approximate location; cannot change protected fields', async () => {
  await assertSucceeds(updateDoc(doc(as('donor1'), 'donor_profiles/donor1'),
    { latitude: 31.52, longitude: 74.35, locationUpdatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('donor1'), 'donor_profiles/donor1'), { isActive: false }));
  await assertFails(updateDoc(doc(as('donor2'), 'donor_profiles/donor1'), { latitude: 1 }));
});

// ---------------- chat ----------------
const acceptedInvite = (extra = {}) => ({ ...invite('donor1'), status: 'accepted', ...extra });
const msg = (uid, text = 'Hello') => ({ senderId: uid, text, createdAt: serverTimestamp() });
const { addDoc, collection } = require('firebase/firestore');

test('chat: donor and receiver can talk while the request is accepted', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), acceptedInvite()));
  const path = 'donor_requests/req1_donor1/messages';
  await assertSucceeds(addDoc(collection(as('receiver1'), path), msg('receiver1')));
  await assertSucceeds(addDoc(collection(as('donor1'), path), msg('donor1', 'On my way')));
});

test('chat: a stranger cannot read or write', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), acceptedInvite()));
  const path = 'donor_requests/req1_donor1/messages';
  await assertFails(addDoc(collection(as('donor2'), path), msg('donor2')));
  await assertFails(getDoc(doc(as('donor2'), path + '/x')));
});

test('chat: cannot send before accept, after complete, as someone else, or too long', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), invite('donor1'))); // still pending
  const path = 'donor_requests/req1_donor1/messages';
  await assertFails(addDoc(collection(as('receiver1'), path), msg('receiver1')));
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), acceptedInvite()));
  await assertFails(addDoc(collection(as('receiver1'), path), msg('donor1')));          // impersonation
  await assertFails(addDoc(collection(as('receiver1'), path), msg('receiver1', 'x'.repeat(1001))));
  await assertFails(addDoc(collection(as('receiver1'), path), { ...msg('receiver1'), extra: 1 }));
  await env.withSecurityRulesDisabled(async (ctx) =>
    setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), acceptedInvite({ status: 'completed' })));
  await assertFails(addDoc(collection(as('receiver1'), path), msg('receiver1')));
});

test('chat: blocked user cannot message the person who blocked them; messages cannot be edited', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1'), acceptedInvite());
    await setDoc(doc(ctx.firestore(), 'users/donor1/blocked/receiver1'), { name: 'R' });
    await setDoc(doc(ctx.firestore(), 'donor_requests/req1_donor1/messages/m1'), { senderId: 'donor1', text: 'hi', createdAt: new Date() });
  });
  await assertFails(addDoc(collection(as('receiver1'), 'donor_requests/req1_donor1/messages'), msg('receiver1')));
  await assertFails(updateDoc(doc(as('donor1'), 'donor_requests/req1_donor1/messages/m1'), { text: 'edited' }));
});

// ---------- blood camps ----------
const camp = (uid) => ({
  title: 'Free blood donation camp', organizer: 'City Hospital', organizerType: 'Hospital',
  city: 'Lahore', address: 'Main Boulevard', date: new Date(Date.now() + 5 * 86400000),
  createdBy: uid, createdAt: serverTimestamp(),
});

test('signed-in user can post a camp as themselves', async () => {
  await assertSucceeds(setDoc(doc(as('donor1'), 'blood_camps/c1'), camp('donor1')));
});

test('cannot post a camp in someone else\'s name or with a bad type', async () => {
  await assertFails(setDoc(doc(as('donor1'), 'blood_camps/c2'), camp('receiver1')));
  await assertFails(setDoc(doc(as('donor1'), 'blood_camps/c3'), { ...camp('donor1'), organizerType: 'Hacker' }));
});

test('only the poster (or admin) can delete a camp; nobody can edit it', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'blood_camps/c4'), { ...camp('donor1'), createdAt: new Date() });
  });
  await assertFails(updateDoc(doc(as('donor1'), 'blood_camps/c4'), { title: 'Changed title' }));
  await assertFails(require('firebase/firestore').deleteDoc(doc(as('receiver1'), 'blood_camps/c4')));
  await assertSucceeds(require('firebase/firestore').deleteDoc(doc(as('donor1'), 'blood_camps/c4')));
});
