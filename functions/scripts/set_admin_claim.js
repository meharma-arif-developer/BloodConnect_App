// Gives (or removes) the `admin` custom claim for one user.
// Run it on YOUR computer. Never share the key file.
//
//   1. Firebase Console > Project settings > Service accounts > Generate new private key
//      (keep the file private, do NOT put it in the project/ZIP)
//   2. PowerShell:
//        $env:GOOGLE_APPLICATION_CREDENTIALS="C:\keys\bloodconnect-admin.json"
//        node scripts/set_admin_claim.js admin@example.com        (make admin)
//        node scripts/set_admin_claim.js admin@example.com remove (remove admin)
//   3. The user must sign out and sign in again to receive the new claim.
const admin = require('firebase-admin');

const email = process.argv[2];
const remove = process.argv[3] === 'remove';
if (!email) {
  console.error('Usage: node scripts/set_admin_claim.js <email> [remove]');
  process.exit(1);
}

admin.initializeApp();
admin
  .auth()
  .getUserByEmail(email)
  .then((user) => admin.auth().setCustomUserClaims(user.uid, remove ? { admin: false } : { admin: true }))
  .then(() => console.log(`${remove ? 'Removed admin from' : 'Admin granted to'} ${email}`))
  .catch((e) => {
    console.error('Failed:', e.message);
    process.exit(1);
  });
