# BloodConnect - Setup Guide and Change Log (latest)

## Languages (12)
English, Urdu, Arabic, Chinese, French, Spanish, German, Turkish, Hindi, Bengali, Indonesian, Russian.
English and Urdu are translated by hand. The other 10 are translated ON THE PHONE by Google ML Kit (`google_mlkit_translation`): free,
works offline after a one-time download of about 30 MB per language. Only the app's own fixed texts are translated, never names or chat
messages. Machine translation is less accurate than a human translation. Arabic and Urdu switch the app to right-to-left automatically.
The chosen language is saved on the phone (`shared_preferences`), so login / signup / onboarding open in it too, and it is also saved
to the account. A globe button on the login, signup and onboarding screens and Profile > Language open the same picker.
If ML Kit is not available (Windows / Linux / Chrome, or the app was only hot-restarted after `flutter pub get`), the app automatically
translates through the free MyMemory online API instead (needs internet; results are saved on the phone). Optional: put your email in
`AppConfig.translateEmail` to raise the free daily limit from 5,000 to 50,000 characters. For the on-phone (offline) way run the app on an
Android phone with Google Play services after `flutter clean` + `flutter pub get` + a full `flutter run`.
To add a language later: add one line in `LanguageController.options` (it must exist in ML Kit).
Code: `lib/l10n/` (`language_controller.dart`, `language_picker.dart`, `machine_translator.dart`, `app_strings.dart`, `app_text.dart`).
After copying run `flutter pub get` (new package `shared_preferences`) and send any build error.

## Blood camps + search any city (latest)
- **Search any city / area** (Community map): type a city or area, the map and the list jump there and show its hospitals, clinics, labs and blood
  banks. Radius 5 / 10 / 20 km. The target button returns to the phone's GPS position; works even without location permission. The full list is
  scrollable and same-name branches are no longer merged. Data comes from OpenStreetMap (free); some places may be missing there.
- **Blood camps** (`lib/screens/community/blood_camps_screen.dart`, `lib/services/camp_service.dart`): any signed-in user (hospital, blood donor, NGO)
  can post a camp / event (title, organizer, type, city, address, date, time, phone, description) into Firestore `blood_camps`. Shown on the Home and
  Community tabs of both dashboards (camps in the user's own city first), in the full list with a city filter ("See all"), and from a calendar
  button on the map. Camps of past days disappear by themselves. Posters can delete their own camp; others can Report it (goes to the Reports tab).
  There is no free internet source of camp events, so camps are posted by users or admins.
- **Admin panel > Blood Camps tab** (`admin_panel/index.html`): lists every camp with WHO posted it (name, email, phone, user ID, time), search, filter
  upcoming / past, **Add camp** (admins can post camps too), **Delete** (asks for a reason and writes it to the Audit Log) and **Suspend poster**.
- **Deploy once:** `firebase deploy --only firestore:rules` (new `blood_camps` rules, 3 new tests in `firestore-rules-tests`) and redeploy the admin
  panel (`firebase deploy --only hosting`, or however it is hosted now). No new Flutter package.

## Round 4 (supervisor feedback)
See `SUPERVISOR_FEEDBACK_STATUS.md`. New: chat (`lib/screens/chat_screen.dart` + rules), one logo for app icon and splash
(`assets/`, Android/iOS/web icons), working Notification Preferences (`lib/widgets/notification_preference_card.dart`),
English + Urdu language (`lib/l10n/`), support email setting `AppConfig.supportEmail`.
After copying the files run: `flutter clean`, `flutter pub get`, `flutter analyze`, then
`firebase deploy --only firestore:rules,firestore:indexes` (the chat needs the new rules) and uninstall the old app before installing.

## Round 3 additions (read this first)
| Item | What was done | Free? |
|---|---|---|
| Free push notifications | `push_relay/` (Cloudflare Workers) + `lib/services/push_relay.dart`. Sends generic pushes: to matching donors on a new request, to a donor on invite, to the receiver on accept/decline/complete. Set `pushRelayUrl` in `lib/config/app_config.dart` after following `push_relay/README.md` | Free (Cloudflare free plan) |
| Admin separate login | Admin accounts are created only with `functions/scripts/create_admin.js` and sign in on the admin website (with forgot-password). The mobile app refuses admin accounts and shows an "Admin Login" link that opens the website | Free |
| Nearby / location | Donors can opt in to share an approximate location (~1 km). Receivers get "Sort by nearest" in Find Donor | Free |
| `lastActive` | Saved when the user opens the app | Free |
| Compatibility | A proposed table is included but stays OFF until a doctor approves it | Free |
| Not added | AdMob (kept out so the build cannot break before testing), Google Maps (billing), Firebase Storage pictures (needs Blaze), multi-language | - |

Create your admin (free, run on your computer):
```powershell
cd C:\FlutterProjects\blood_connect\functions
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\FlutterProjects\admin.json"
node scripts/create_admin.js admin@example.com "a-strong-password-here"
```
Use a NEW admin email that is not used by a donor/receiver account.


> **Honest status.** Flutter and the Firebase Emulator are not available where this code was written, so it has NOT been
> compiled or run. Verified only: bracket balance of every edited Dart file, and that `functions/index.js`, the admin
> panel script and the rules-test file load / pass a Node syntax check. Run section 2 and send any error text.

## 1. What is new in this version
| # | Request | What was done | Free plan? |
|---|---|---|---|
| 1 | Email code at login | Built end to end (`email_otp_screen.dart`, functions `sendLoginOtp` / `verifyLoginOtp`, code stored hashed, 10 min expiry, 5 tries, 1 resend/min). **Switched OFF** by default | **No.** Needs Blaze + a Brevo email key |
| 2 | Light mode after login | New accounts get `Light`. Old accounts that were saved as "System Default" also start Light unless the user chose System in Settings. User can still change it in Settings | Free |
| 3 | Better admin dashboard | Redesigned: sidebar, statistics cards, bar charts, filters, search, confirmation windows, toasts, audit log tab | Free |
| 4 | Better UI | App-wide polish through the theme (smoother page transitions, rounded dialogs / sheets / snackbars, themed progress and buttons). Signup has Country, City, Area. Per-screen redesign was NOT done (needs your screenshots / wishes) | Free |
| 5 | Make it work without Blaze | Suspension now works with Firestore rules only. Live in-app alerts added. Push and email code are behind switches in `lib/config/app_config.dart` (both `false`) | Free |
| 6 | International | Country dropdown, International phone validation, country-aware matching, city matching ignores ", Area" | Free |
| 7 | Missing requirements | Area field, compatibility mechanism (disabled), consent, removed fake-data notifications screen, `REQUIREMENTS_STATUS.md` for your supervisor | Free |

Files changed or added this round: `lib/config/*` (new), `lib/services/{account_gate,live_alerts,app_messenger}.dart` (new),
`lib/screens/email_otp_screen.dart` (new), `main.dart`, `login_screen.dart`, `splash_screen.dart`, `signup_screen.dart`,
`edit_profile_screen.dart`, `profile_screen.dart`, `request_blood_screen.dart`, `find_donor_screen.dart`, both dashboards,
`firestore.rules`, `functions/index.js`, `admin_panel/index.html`, `pubspec.yaml` (added `cloud_functions`).
Deleted: `notifications_screen.dart` (unused, fake data).

## 2. Run (Windows, PowerShell, one by one)
```powershell
cd C:\FlutterProjects\blood_connect
flutter pub get
flutter analyze
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only hosting
flutter run
```
`firebase deploy --only firestore:rules` is REQUIRED again: the rules changed (suspension, audit log).
`flutter pub get` now also downloads `cloud_functions`. Send me any version-conflict message.

## 3. Admin (free)
1. Make your admin (once): `cd functions`, `npm install`, set `GOOGLE_APPLICATION_CREDENTIALS` to your key file, then
   `node scripts/set_admin_claim.js your-email`. Keep the key file OUT of the project folder.
2. Open `https://bloodconnect-f8c69.web.app`, sign out/in first so the admin permission loads.
3. Suspend / Enable now works without Blaze.

## 4. Only if you later choose Blaze
Blaze has a free monthly quota but needs a card. Set a billing budget alert first.
- Push: set `pushEnabled = true` in `lib/config/app_config.dart`, then `firebase deploy --only functions`.
  iOS also needs Xcode Push capability + APNs key.
- Email code: create a Brevo account (free tier), verify a sender email, create an API key, then
  `firebase functions:secrets:set BREVO_API_KEY`, set `OTP_SENDER_EMAIL` when asked at deploy, deploy functions, and set
  `emailOtpEnabled = true`. Note: the code screen is an extra step after the password; it is not a server-enforced lock.

## 5. Not done / limits
- Nothing run by me. Expect to fix some compile errors.
- Blood-group compatibility table: must be written by a doctor / blood bank (see `lib/config/blood_compatibility.dart`).
- No distance search, no lat/long, no Google Maps, no AdMob, no multi-language, no Firebase Storage pictures.
- A suspended user keeps a valid login token, but rules block their writes and the app signs them out.
- Legal text is a draft needing professional review.
- Release steps still open: app ID `com.example.blood_connect`, signing key, icon, store listing.
