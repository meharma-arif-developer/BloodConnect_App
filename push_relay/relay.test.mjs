// Offline tests with FAKE Google / Firestore / FCM servers (no network needed).
import { test, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import { handleNotify, verifyIdToken } from './worker.js';

const PROJECT = 'bloodconnect-test';
const b64u = (b) => Buffer.from(b).toString('base64url');
const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'RS256', use: 'sig' };
const saKey = generateKeyPairSync('rsa', { modulusLength: 2048 });

function idToken(uid, over = {}) {
  const now = Math.floor(Date.now() / 1000);
  const h = b64u(JSON.stringify({ alg: 'RS256', kid: 'k1', typ: 'JWT' }));
  const p = b64u(JSON.stringify({ aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, sub: uid, iat: now, exp: now + 3600, ...over }));
  const sig = createSign('RSA-SHA256').update(`${h}.${p}`).sign(privateKey);
  return `${h}.${p}.${b64u(sig)}`;
}

// ---- fake backend state ----
let docs, sentPushes, patches;
const env = {
  FIREBASE_PROJECT_ID: PROJECT,
  SERVICE_ACCOUNT_JSON: JSON.stringify({
    client_email: 'relay@test.iam.gserviceaccount.com',
    private_key: saKey.privateKey.export({ type: 'pkcs8', format: 'pem' }),
  }),
};
const fv = (v) => typeof v === 'boolean' ? { booleanValue: v } : { stringValue: String(v) };
const toDoc = (o) => ({ fields: Object.fromEntries(Object.entries(o).map(([k, v]) => [k, fv(v)])) });

before(() => {
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    const ok = (obj, status = 200) => new Response(JSON.stringify(obj), { status });
    if (url.includes('/jwk/securetoken')) return ok({ keys: [jwk] });
    if (url.startsWith('https://oauth2.googleapis.com/token')) return ok({ access_token: 'AT', expires_in: 3600 });
    if (url.includes('fcm.googleapis.com')) { sentPushes.push(JSON.parse(init.body).message); return ok({ name: 'm' }); }
    const base = '/documents/';
    if (url.includes(':runQuery')) {
      const q = JSON.parse(init.body).structuredQuery;
      const group = q.where.compositeFilter.filters[0].fieldFilter.value.stringValue;
      const rows = Object.entries(docs).filter(([p, d]) => p.startsWith('donor_profiles/') && d.bloodGroup === group && d.donorAvailable === true)
        .map(([p, d]) => ({ document: { name: `x/${p}`, ...toDoc(d) } }));
      return ok(rows.length ? rows : [{}]);
    }
    const path = decodeURIComponent(url.split(base)[1].split('?')[0]);
    if (init.method === 'PATCH') { const f = url.split('updateMask.fieldPaths=')[1]; patches.push([path, f]); docs[path] = { ...(docs[path] || {}), [f]: JSON.parse(init.body).fields[f].stringValue }; return ok({}); }
    if (init.method === 'DELETE') { delete docs[path]; return ok({}); }
    if (path.endsWith('/fcm_tokens')) {
      const prefix = path + '/';
      return ok({ documents: Object.keys(docs).filter((p) => p.startsWith(prefix)).map((p) => ({ name: `x/${p}` })) });
    }
    return docs[path] ? ok(toDoc(docs[path])) : new Response('{}', { status: 404 });
  };
});

beforeEach(() => {
  sentPushes = []; patches = [];
  docs = {
    'users/receiver1': { role: 'receiver' },
    'users/donor1': { role: 'donor' }, 'users/donor2': { role: 'donor' }, 'users/donor3': { role: 'donor', notificationsEnabled: false },
    'users/donor1/fcm_tokens/tokA': { platform: 'android' },
    'users/donor2/fcm_tokens/tokB': { platform: 'android' },
    'users/donor3/fcm_tokens/tokC': { platform: 'android' },
    'users/receiver1/fcm_tokens/tokR': { platform: 'android' },
    'donor_profiles/donor1': { bloodGroup: 'O+', donorAvailable: true, city: 'Lahore', country: 'Pakistan' },
    'donor_profiles/donor2': { bloodGroup: 'O+', donorAvailable: true, city: 'Karachi', country: 'Pakistan' },
    'donor_profiles/donor3': { bloodGroup: 'O+', donorAvailable: true, city: 'Lahore', country: 'Pakistan' },
    'blood_requests/req12345': { requesterId: 'receiver1', bloodGroup: 'O+', city: 'Lahore', country: 'Pakistan', status: 'pending' },
    'donor_requests/req12345_donor1': { requesterId: 'receiver1', donorId: 'donor1', bloodRequestId: 'req12345', status: 'pending' },
  };
});

const call = (token, body) => handleNotify(new Request('https://relay.test/notify', {
  method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body),
}), env);

test('token checks: good, wrong project, expired, tampered', async () => {
  assert.equal((await verifyIdToken(idToken('u1'), PROJECT)).sub, 'u1');
  await assert.rejects(verifyIdToken(idToken('u1', { aud: 'other' }), PROJECT));
  await assert.rejects(verifyIdToken(idToken('u1', { exp: 1 }), PROJECT));
  const t = idToken('u1').split('.'); t[1] = b64u(JSON.stringify({ aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, sub: 'admin', exp: 9999999999 }));
  await assert.rejects(verifyIdToken(t.join('.'), PROJECT));
});

test('no / bad token is rejected with 401', async () => {
  assert.equal((await call('garbage', { type: 'invite', id: 'req12345_donor1' })).status, 401);
});

test('invite: requester triggers one push to the donor, only once', async () => {
  const r1 = await (await call(idToken('receiver1'), { type: 'invite', id: 'req12345_donor1' })).json();
  assert.equal(r1.sent, 1); assert.equal(sentPushes.length, 1); assert.equal(sentPushes[0].token, 'tokA');
  assert.ok(!JSON.stringify(sentPushes[0]).match(/O\+|Lahore|hospital|phone/i), 'push text must stay generic');
  const r2 = await (await call(idToken('receiver1'), { type: 'invite', id: 'req12345_donor1' })).json();
  assert.equal(r2.sent, 0); assert.equal(sentPushes.length, 1);
});

test('invite: someone else cannot trigger it', async () => {
  assert.equal((await call(idToken('donor2'), { type: 'invite', id: 'req12345_donor1' })).status, 403);
  assert.equal(sentPushes.length, 0);
});

test('response: only the invited donor, after a real response', async () => {
  assert.equal((await call(idToken('donor1'), { type: 'response', id: 'req12345_donor1' })).status, 403); // still pending
  docs['donor_requests/req12345_donor1'].status = 'accepted';
  assert.equal((await call(idToken('receiver1'), { type: 'response', id: 'req12345_donor1' })).status, 403); // wrong caller
  const r = await (await call(idToken('donor1'), { type: 'response', id: 'req12345_donor1' })).json();
  assert.equal(r.sent, 1); assert.equal(sentPushes[0].token, 'tokR');
});

test('request: notifies only matching, enabled, unblocked donors (same city), once', async () => {
  docs['users/donor1/blocked/receiver1'] = { name: 'x' };
  docs['donor_profiles/donor4'] = { bloodGroup: 'O+', donorAvailable: true, city: 'Lahore, Johar Town', country: 'Pakistan' };
  docs['users/donor4'] = { role: 'donor' }; docs['users/donor4/fcm_tokens/tokD'] = {};
  const r = await (await call(idToken('receiver1'), { type: 'request', id: 'req12345' })).json();
  // donor1 blocked, donor2 other city, donor3 notifications off, donor4 matches
  assert.equal(r.sent, 1); assert.equal(sentPushes[0].token, 'tokD');
  const again = await (await call(idToken('receiver1'), { type: 'request', id: 'req12345' })).json();
  assert.equal(again.sent, 0);
});

test('request: a stranger cannot trigger notifications for someone else\'s request', async () => {
  assert.equal((await call(idToken('donor1'), { type: 'request', id: 'req12345' })).status, 403);
});

test('suspended callers are refused', async () => {
  docs['suspended_users/receiver1'] = { reason: 'spam' };
  assert.equal((await call(idToken('receiver1'), { type: 'invite', id: 'req12345_donor1' })).status, 403);
});

test('message: the other person gets one generic push, only once', async () => {
  docs['donor_requests/req12345_donor1'].status = 'accepted';
  docs['donor_requests/req12345_donor1/messages/msgABCDE1'] = { senderId: 'receiver1', text: 'secret hospital 5 pm' };
  const r1 = await (await call(idToken('receiver1'), { type: 'message', id: 'req12345_donor1', messageId: 'msgABCDE1' })).json();
  assert.equal(r1.sent, 1); assert.equal(sentPushes[0].token, 'tokA');
  assert.ok(!JSON.stringify(sentPushes[0]).match(/secret|hospital|5 pm/i), 'message text must never be in the push');
  const r2 = await (await call(idToken('receiver1'), { type: 'message', id: 'req12345_donor1', messageId: 'msgABCDE1' })).json();
  assert.equal(r2.sent, 0); assert.equal(sentPushes.length, 1);
});

test('message: wrong sender, stranger, or non-accepted chat is refused', async () => {
  docs['donor_requests/req12345_donor1/messages/msgABCDE1'] = { senderId: 'receiver1', text: 'hi' };
  const body = { type: 'message', id: 'req12345_donor1', messageId: 'msgABCDE1' };
  assert.equal((await call(idToken('receiver1'), body)).status, 403);          // request still pending
  docs['donor_requests/req12345_donor1'].status = 'accepted';
  assert.equal((await call(idToken('donor1'), body)).status, 403);             // not the sender of that message
  assert.equal((await call(idToken('donor2'), body)).status, 403);             // stranger
  assert.equal(sentPushes.length, 0);
});

test('message: no push to someone who blocked the sender', async () => {
  docs['donor_requests/req12345_donor1'].status = 'accepted';
  docs['users/donor1/blocked/receiver1'] = { name: 'x' };
  docs['donor_requests/req12345_donor1/messages/msgABCDE1'] = { senderId: 'receiver1', text: 'hi' };
  const r = await (await call(idToken('receiver1'), { type: 'message', id: 'req12345_donor1', messageId: 'msgABCDE1' })).json();
  assert.equal(r.sent, 0); assert.equal(sentPushes.length, 0);
});
