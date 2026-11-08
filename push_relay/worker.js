// BloodConnect FREE push relay (Cloudflare Workers, free plan, no Blaze needed).
//
// The app calls  POST /notify  with its Firebase login token and { type, id }.
// This worker:
//   1. verifies the login token (Google public keys),
//   2. checks in Firestore that the caller is allowed to trigger that push,
//   3. sends a GENERIC push (no blood group / hospital / phone) through FCM.
//
// Secrets: SERVICE_ACCOUNT_JSON (a restricted service account), var FIREBASE_PROJECT_ID.

const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const MAX_DONORS_PER_REQUEST = 30;

// ---------- small helpers ----------
const enc = new TextEncoder();
const b64urlToBytes = (s) => {
  s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '=';
  const bin = atob(s); const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
};
const bytesToB64url = (bytes) => {
  let bin = ''; for (const b of new Uint8Array(bytes)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const jsonB64url = (obj) => bytesToB64url(enc.encode(JSON.stringify(obj)));
const parseJson = (bytes) => JSON.parse(new TextDecoder().decode(bytes));
const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

// ---------- 1. verify the Firebase ID token ----------
let jwksCache = { keys: null, at: 0 };
async function getJwks() {
  if (jwksCache.keys && Date.now() - jwksCache.at < 3600 * 1000) return jwksCache.keys;
  const res = await fetch(JWKS_URL);
  if (!res.ok) throw new Error('Could not load Google keys');
  jwksCache = { keys: (await res.json()).keys, at: Date.now() };
  return jwksCache.keys;
}

export async function verifyIdToken(token, projectId) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) throw new Error('bad token');
  const header = parseJson(b64urlToBytes(parts[0]));
  const payload = parseJson(b64urlToBytes(parts[1]));
  if (header.alg !== 'RS256' || !header.kid) throw new Error('bad header');

  const jwk = (await getJwks()).find((k) => k.kid === header.kid);
  if (!jwk) throw new Error('unknown key');
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlToBytes(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new Error('bad signature');

  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== projectId) throw new Error('bad audience');
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) throw new Error('bad issuer');
  if (!payload.exp || payload.exp <= now) throw new Error('expired');
  if (payload.iat && payload.iat > now + 60) throw new Error('bad iat');
  if (!payload.sub) throw new Error('no subject');
  return payload;
}

// ---------- 2. Google access token from the service account ----------
let tokenCache = { value: null, exp: 0 };
async function getAccessToken(env) {
  if (tokenCache.value && Date.now() < tokenCache.exp - 60000) return tokenCache.value;
  const sa = JSON.parse(env.SERVICE_ACCOUNT_JSON);
  const iat = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat, exp: iat + 3600,
  };
  const unsigned = `${jsonB64url({ alg: 'RS256', typ: 'JWT' })}.${jsonB64url(claim)}`;
  const pem = sa.private_key.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(unsigned));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${bytesToB64url(sig)}` }),
  });
  if (!res.ok) throw new Error('Could not get access token');
  const data = await res.json();
  tokenCache = { value: data.access_token, exp: Date.now() + data.expires_in * 1000 };
  return tokenCache.value;
}

// ---------- 3. tiny Firestore REST client ----------
function decodeValue(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  return undefined;
}
const decodeFields = (f) => Object.fromEntries(Object.entries(f || {}).map(([k, v]) => [k, decodeValue(v)]));

function makeFirestore(env, accessToken) {
  const base = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
  const headers = { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' };
  return {
    async get(path) {
      const res = await fetch(`${base}/${path}`, { headers });
      if (res.status === 404) return null;
      if (!res.ok) throw new Error(`Firestore get failed (${res.status})`);
      return decodeFields((await res.json()).fields);
    },
    async exists(path) { return (await this.get(path)) !== null; },
    async list(path) {
      const res = await fetch(`${base}/${path}?pageSize=20`, { headers });
      if (!res.ok) return [];
      return ((await res.json()).documents || []).map((d) => d.name.split('/').pop());
    },
    async patchString(path, field, value) {
      await fetch(`${base}/${path}?updateMask.fieldPaths=${field}`, {
        method: 'PATCH', headers, body: JSON.stringify({ fields: { [field]: { stringValue: value } } }),
      });
    },
    async remove(path) { await fetch(`${base}/${path}`, { method: 'DELETE', headers }); },
    async matchingDonors(bloodGroup) {
      const res = await fetch(`${base}:runQuery`, {
        method: 'POST', headers,
        body: JSON.stringify({ structuredQuery: {
          from: [{ collectionId: 'donor_profiles' }],
          where: { compositeFilter: { op: 'AND', filters: [
            { fieldFilter: { field: { fieldPath: 'bloodGroup' }, op: 'EQUAL', value: { stringValue: bloodGroup } } },
            { fieldFilter: { field: { fieldPath: 'donorAvailable' }, op: 'EQUAL', value: { booleanValue: true } } },
          ] } },
          limit: 200,
        } }),
      });
      if (!res.ok) throw new Error('Donor query failed');
      return (await res.json()).filter((r) => r.document).map((r) => ({ id: r.document.name.split('/').pop(), ...decodeFields(r.document.fields) }));
    },
  };
}

// ---------- 4. FCM ----------
async function pushToUser(fs, env, accessToken, uid, title, body, type) {
  const user = await fs.get(`users/${uid}`);
  if (!user || user.notificationsEnabled === false || user.isActive === false) return 0;
  let sent = 0;
  for (const token of await fs.list(`users/${uid}/fcm_tokens`)) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
      method: 'POST', headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ message: { token, notification: { title, body }, data: { type }, android: { priority: 'high' } } }),
    });
    if (res.ok) sent++;
    else if (res.status === 404 || res.status === 400) await fs.remove(`users/${uid}/fcm_tokens/${token}`);
  }
  return sent;
}

const norm = (v) => String(v ?? '').trim().toLowerCase();
const cityKey = (v) => norm(v).split(',')[0].trim();

// ---------- 5. the endpoint ----------
export async function handleNotify(request, env) {
  if (request.method !== 'POST') return json({ error: 'POST only' }, 405);

  let uid;
  try {
    const auth = request.headers.get('authorization') || '';
    uid = (await verifyIdToken(auth.replace(/^Bearer\s+/i, ''), env.FIREBASE_PROJECT_ID)).sub;
  } catch (e) { return json({ error: 'unauthorized' }, 401); }

  let body;
  try { body = await request.json(); } catch (e) { return json({ error: 'bad json' }, 400); }
  const { type, id } = body || {};
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{5,200}$/.test(id)) return json({ error: 'bad id' }, 400);

  const accessToken = await getAccessToken(env);
  const fs = makeFirestore(env, accessToken);

  if (await fs.exists(`suspended_users/${uid}`)) return json({ error: 'suspended' }, 403);

  if (type === 'request') {
    const req = await fs.get(`blood_requests/${id}`);
    if (!req || req.requesterId !== uid) return json({ error: 'forbidden' }, 403);
    if (req.pushNotifiedAt) return json({ ok: true, sent: 0, note: 'already notified' });
    await fs.patchString(`blood_requests/${id}`, 'pushNotifiedAt', new Date().toISOString());

    let sent = 0, count = 0;
    for (const d of await fs.matchingDonors(req.bloodGroup)) {
      if (count >= MAX_DONORS_PER_REQUEST) break;
      if (d.id === uid || d.isActive === false) continue;
      if (req.country && d.country && norm(req.country) !== norm(d.country)) continue;
      if (cityKey(req.city) && cityKey(d.city) && cityKey(req.city) !== cityKey(d.city)) continue;
      if (await fs.exists(`users/${d.id}/blocked/${uid}`)) continue;
      count++;
      sent += await pushToUser(fs, env, accessToken, d.id, 'Blood needed nearby', 'Someone may need your help. Open BloodConnect to see if you can respond.', 'new_request');
    }
    return json({ ok: true, sent });
  }

  if (type === 'message') {
    const messageId = body.messageId;
    if (typeof messageId !== 'string' || !/^[A-Za-z0-9_-]{5,200}$/.test(messageId)) return json({ error: 'bad id' }, 400);

    const chat = await fs.get(`donor_requests/${id}`);
    if (!chat) return json({ error: 'not found' }, 404);
    if ((chat.donorId !== uid && chat.requesterId !== uid) || chat.status !== 'accepted') return json({ error: 'forbidden' }, 403);

    const messagePath = `donor_requests/${id}/messages/${messageId}`;
    const message = await fs.get(messagePath);
    if (!message || message.senderId !== uid) return json({ error: 'forbidden' }, 403);
    if (message.pushNotified) return json({ ok: true, sent: 0, note: 'already notified' });
    await fs.patchString(messagePath, 'pushNotified', new Date().toISOString());

    const other = chat.donorId === uid ? chat.requesterId : chat.donorId;
    if (await fs.exists(`users/${other}/blocked/${uid}`)) return json({ ok: true, sent: 0 });

    // Generic text only: the message itself never appears on a lock screen.
    const sent = await pushToUser(fs, env, accessToken, other, 'New message', 'You have a new message. Open BloodConnect to read it.', 'chat_message');
    return json({ ok: true, sent });
  }

  const dr = (type === 'invite' || type === 'response') ? await fs.get(`donor_requests/${id}`) : null;
  if (!dr) return json({ error: type === 'invite' || type === 'response' ? 'not found' : 'bad type' }, type === 'invite' || type === 'response' ? 404 : 400);

  if (type === 'invite') {
    if (dr.requesterId !== uid || dr.status !== 'pending') return json({ error: 'forbidden' }, 403);
    if (dr.pushInviteSent) return json({ ok: true, sent: 0, note: 'already notified' });
    await fs.patchString(`donor_requests/${id}`, 'pushInviteSent', new Date().toISOString());
    const sent = await pushToUser(fs, env, accessToken, dr.donorId, 'New blood request', 'You have a new request. Open BloodConnect to view and respond.', 'donor_request');
    return json({ ok: true, sent });
  }

  // type === 'response'
  if (dr.donorId !== uid || !['accepted', 'rejected', 'completed'].includes(dr.status)) return json({ error: 'forbidden' }, 403);
  if (dr.pushNotifiedStatus === dr.status) return json({ ok: true, sent: 0, note: 'already notified' });
  await fs.patchString(`donor_requests/${id}`, 'pushNotifiedStatus', dr.status);
  const texts = {
    accepted: ['Donor accepted', 'A donor accepted your request. Open BloodConnect for details.'],
    rejected: ['Donor unavailable', 'A donor could not help with your request.'],
    completed: ['Request completed', 'Your blood request was marked as completed.'],
  }[dr.status];
  const sent = await pushToUser(fs, env, accessToken, dr.requesterId, texts[0], texts[1], 'request_update');
  return json({ ok: true, sent });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/' && request.method === 'GET') return json({ service: 'BloodConnect push relay', ok: true });
    if (url.pathname === '/notify') {
      try { return await handleNotify(request, env); }
      catch (e) { return json({ error: 'server error' }, 500); }
    }
    return json({ error: 'not found' }, 404);
  },
};
