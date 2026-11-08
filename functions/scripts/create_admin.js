// Creates a SEPARATE administrator account (it is NOT a donor/receiver account).
// Run on YOUR computer. Never share the key file or the password.
//
//   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\keys\admin.json"
//   node scripts/create_admin.js admin@example.com "A-strong-password-12"
//
// The admin signs in on the ADMIN WEBSITE only. In the mobile app this
// account is refused with a message pointing to the admin website.
const admin = require('firebase-admin');

const [email, password] = process.argv.slice(2);
if (!email || !password || password.length < 10) {
  console.error('Usage: node scripts/create_admin.js <email> "<password, at least 10 characters>"');
  process.exit(1);
}

admin.initializeApp();

(async () => {
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(user.uid, { password });
    console.log('Existing account found - password updated.');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await admin.auth().createUser({ email, password, emailVerified: true, displayName: 'BloodConnect Admin' });
    console.log('New admin account created.');
  }
  await admin.auth().setCustomUserClaims(user.uid, { admin: true });
  console.log(`Admin permission granted to ${email}. Sign in on the admin website.`);
})().catch((e) => { console.error('Failed:', e.message); process.exit(1); });
