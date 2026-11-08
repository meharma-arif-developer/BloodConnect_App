// BloodConnect - trusted backend code (Cloud Functions, Node 22).
// Needs the Firebase Blaze plan to deploy.
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const functionsV1 = require('firebase-functions/v1');
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const { defineSecret, defineString } = require('firebase-functions/params');

admin.initializeApp();
const db = admin.firestore();

// ---------------------------------------------------------------
// Push helper. Message text is intentionally generic so no private
// medical/contact detail ever appears on a lock screen.
// ---------------------------------------------------------------
async function pushToUser(uid, title, body, type) {
  if (!uid) return;

  const userSnap = await db.doc(`users/${uid}`).get();
  if (!userSnap.exists || userSnap.get('notificationsEnabled') === false) return;

  const tokenSnap = await db.collection(`users/${uid}/fcm_tokens`).get();
  const tokens = tokenSnap.docs.map((d) => d.id);
  if (tokens.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type },
  });

  // Remove tokens that are no longer valid.
  const stale = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      stale.push(tokens[i]);
    }
  });
  await Promise.all(stale.map((t) => db.doc(`users/${uid}/fcm_tokens/${t}`).delete()));
}

// A requester invited a donor -> notify the donor.
exports.notifyDonorOnInvite = onDocumentCreated('donor_requests/{id}', async (event) => {
  const data = event.data && event.data.data();
  if (!data || data.status !== 'pending') return;
  await pushToUser(
    data.donorId,
    'New blood request',
    'Someone needs your help. Open BloodConnect to view and respond.',
    'donor_request',
  );
});

// A donor responded -> notify the requester (only on status change).
exports.notifyRequesterOnResponse = onDocumentUpdated('donor_requests/{id}', async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!before || !after || before.status === after.status) return;

  const messages = {
    accepted: ['Donor accepted', 'A donor accepted your request. Open BloodConnect for details.'],
    rejected: ['Donor unavailable', 'A donor could not help with your request.'],
    completed: ['Request completed', 'Your blood request was marked as completed.'],
  };
  const m = messages[after.status];
  if (!m) return;
  await pushToUser(after.requesterId, m[0], m[1], 'request_update');
});

// A new blood request -> notify matching donors (same blood group, available,
// same country + city, not blocked, notifications on). At most 30 donors.
exports.notifyMatchingDonors = onDocumentCreated('blood_requests/{id}', async (event) => {
  const req = event.data && event.data.data();
  if (!req || req.status !== 'pending' || !req.bloodGroup) return;

  const norm = (v) => String(v ?? '').trim().toLowerCase();
  const cityKey = (v) => norm(v).split(',')[0].trim();

  const snap = await db.collection('donor_profiles')
    .where('bloodGroup', '==', req.bloodGroup)
    .where('donorAvailable', '==', true)
    .limit(200).get();

  let count = 0;
  for (const d of snap.docs) {
    if (count >= 30) break;
    const donor = d.data();
    if (d.id === req.requesterId || donor.isActive === false) continue;
    if (req.country && donor.country && norm(req.country) !== norm(donor.country)) continue;
    if (cityKey(req.city) && cityKey(donor.city) && cityKey(req.city) !== cityKey(donor.city)) continue;
    if ((await db.doc(`users/${d.id}/blocked/${req.requesterId}`).get()).exists) continue;
    count++;
    await pushToUser(d.id, 'Blood needed nearby',
      'Someone may need your help. Open BloodConnect to see if you can respond.', 'new_request');
  }
});

// A chat message -> notify the other person (generic text, never the message).
exports.notifyOnChatMessage = onDocumentCreated('donor_requests/{id}/messages/{msgId}', async (event) => {
  const msg = event.data && event.data.data();
  if (!msg) return;
  const chat = (await db.doc(`donor_requests/${event.params.id}`).get()).data();
  if (!chat || chat.status !== 'accepted') return;
  if (msg.senderId !== chat.donorId && msg.senderId !== chat.requesterId) return;

  const other = msg.senderId === chat.donorId ? chat.requesterId : chat.donorId;
  if ((await db.doc(`users/${other}/blocked/${msg.senderId}`).get()).exists) return;

  await pushToUser(other, 'New message',
    'You have a new message. Open BloodConnect to read it.', 'chat_message');
});

// ---------------------------------------------------------------
// OPTIONAL email login code (OTP). Used only when
// AppConfig.emailOtpEnabled = true in the Flutter app.
// The code is stored HASHED, expires in 10 minutes, allows 5 tries,
// and can be re-sent at most once a minute.
// Needs: Blaze plan + a Brevo account (see SETUP_AND_CHANGES.md).
// ---------------------------------------------------------------
const BREVO_API_KEY = defineSecret('BREVO_API_KEY');
const OTP_SENDER_EMAIL = defineString('OTP_SENDER_EMAIL');

exports.sendLoginOtp = onCall({ secrets: [BREVO_API_KEY] }, async (request) => {
  if (!request.auth || !request.auth.token.email) {
    throw new HttpsError('unauthenticated', 'Please log in first.');
  }
  const uid = request.auth.uid;
  const email = request.auth.token.email;
  const ref = db.doc(`otp_codes/${uid}`);
  const now = Date.now();

  const snap = await ref.get();
  if (snap.exists && now - (snap.get('sentAtMs') || 0) < 60 * 1000) {
    throw new HttpsError('resource-exhausted', 'Please wait a minute before asking for a new code.');
  }

  const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.createHash('sha256').update(salt + code).digest('hex');
  await ref.set({ hash, salt, sentAtMs: now, expiresAtMs: now + 10 * 60 * 1000, attempts: 0 });

  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': BREVO_API_KEY.value(), 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({
      sender: { name: 'BloodConnect', email: OTP_SENDER_EMAIL.value() },
      to: [{ email }],
      subject: 'Your BloodConnect login code',
      textContent: `Your BloodConnect verification code is ${code}. It expires in 10 minutes. If you did not try to log in, please ignore this email.`,
    }),
  });
  if (!res.ok) {
    await ref.delete();
    throw new HttpsError('internal', 'Could not send the code. Please try again.');
  }
  return { ok: true };
});

exports.verifyLoginOtp = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please log in first.');
  const code = request.data && request.data.code;
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
  }

  const ref = db.doc(`otp_codes/${request.auth.uid}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'No code found. Please request a new one.');

  const d = snap.data();
  if (Date.now() > d.expiresAtMs) {
    await ref.delete();
    throw new HttpsError('deadline-exceeded', 'The code has expired. Please request a new one.');
  }
  if (d.attempts >= 5) {
    await ref.delete();
    throw new HttpsError('resource-exhausted', 'Too many wrong attempts. Please request a new code.');
  }

  const given = crypto.createHash('sha256').update(d.salt + code).digest();
  const stored = Buffer.from(d.hash, 'hex');
  if (given.length !== stored.length || !crypto.timingSafeEqual(given, stored)) {
    await ref.update({ attempts: admin.firestore.FieldValue.increment(1) });
    throw new HttpsError('permission-denied', 'Wrong code. Please try again.');
  }

  await ref.delete();
  return { ok: true };
});

// ---------------------------------------------------------------
// When an Auth account is deleted, remove its private subcollections
// (the app cannot delete them itself).
// ---------------------------------------------------------------
exports.cleanupDeletedUser = functionsV1.auth.user().onDelete(async (user) => {
  await db.recursiveDelete(db.doc(`users/${user.uid}`));
  await db.doc(`donor_profiles/${user.uid}`).delete().catch(() => {});
});
