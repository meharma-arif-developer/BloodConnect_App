// Lists every administrator account (accounts that have the admin permission).
// Run on YOUR computer. Never share the key file.
//
//   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\admin-key.json"
//   node scripts/list_admins.js
//
// To remove someone's admin permission:
//   node scripts/set_admin_claim.js their-email@example.com remove
const admin = require('firebase-admin');

admin.initializeApp();

(async () => {
  const admins = [];
  let pageToken;

  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const user of page.users) {
      if (user.customClaims && user.customClaims.admin === true) admins.push(user);
    }
    pageToken = page.pageToken;
  } while (pageToken);

  if (admins.length === 0) {
    console.log('No administrators found.');
    return;
  }

  console.log(`Administrators (${admins.length}):`);
  for (const user of admins) {
    console.log(
      `- ${user.email || '(no email)'} | disabled: ${user.disabled} | last sign-in: ${user.metadata.lastSignInTime || 'never'}`
    );
  }
})().catch((e) => {
  console.error('Failed:', e.message);
  process.exit(1);
});
