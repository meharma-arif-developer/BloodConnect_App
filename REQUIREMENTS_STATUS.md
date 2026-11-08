# BloodConnect - Requirements vs. Current Status

**Important:** "Built" means the code is written. The developer's environment could not run Flutter, so nothing below
has been confirmed on a real phone yet. A status marked *Built, needs device test* must be tested before release.

Legend: **Built** = code written | **Free** = works on the free Firebase (Spark) plan | **Blaze** = needs paid plan (has a free monthly quota)

## 1. Users and roles
| Requirement | Status |
|---|---|
| Donor: profile, blood group, country, city, **area**, availability | Built, needs device test (area + country added) |
| Donor: receive requests, accept / decline | Built, needs device test. Free |
| Receiver: register, emergency request (blood group, units, hospital, location, urgency, date, description) | Built, needs device test. Free |
| Receiver: see matching donors, send request | Built, needs device test. Free |
| Admin: manage users, review reports, manage requests, statistics | Built (web panel, redesigned). Needs deploy + test. Free |
| Admin has a SEPARATE login | Built: admins sign in only on the admin website (own accounts created with `create_admin.js`, no app signup). The mobile app refuses admin accounts and has an "Admin Login" link. Free |
| Admin: disable fraudulent / spam accounts | Built (suspend / enable with reason + audit log). Free (rule-enforced, no paid plan needed) |

## 2. Authentication
| Requirement | Status |
|---|---|
| Email / password register + login, password reset, role routing, logout | Built (pre-existing) |
| Email code (OTP) after login | Built but **switched off**. Needs Blaze + email service. Cannot be done securely on the free plan |
| Consent at registration | Built |
| Suspended accounts blocked | Built. Free |

## 3. Privacy and safety
| Requirement | Status |
|---|---|
| Phone numbers not public; contact shared only after donor accepts | Built, needs device test |
| Report user, block user, blocked-users list | Built, needs device test |
| Delete account | Built |
| `lastActive` | Built |
| Privacy Policy, Terms, medical disclaimer | Built, **draft text - needs professional review** |
| Minimal data collection | Built |

## 4. Matching
| Requirement | Status |
|---|---|
| Blood group | Exact match (safe default) |
| Potentially compatible groups | Mechanism built and a *proposed* table is included, but **disabled**: a doctor / blood bank must approve it first |
| Location | Country + city must match; same **area** first. Donors can OPT IN to share an approximate location (about 1 km); receivers can tap "Sort by nearest" |
| Availability + active account | Built |
| Automatic notifications to matching donors | Built through the FREE push relay (up to 30 matching donors per request). Needs the one-time Cloudflare setup, not tested on real services yet |

## 5. Notifications
| Requirement | Status |
|---|---|
| In-app alerts (Alerts tab) | Built. Free |
| Live banner while the app is open | Built. Free |
| Push notification when app is closed | FREE option built (`push_relay/`, Cloudflare Workers, 8 offline tests pass). Needs one-time setup + real-device test. iPhone also needs Apple developer account. The Blaze/Cloud Functions route is still available |

## 6. International
| Requirement | Status |
|---|---|
| Country selection (40 countries), city, area | Built |
| International phone numbers | Built |
| Matching respects country | Built |
| Multiple app languages | Not built (English only). Large job; recommended after core testing |
| Time zones | Dates are stored as server timestamps; local display only |

## 7. Technology
| Requirement | Status |
|---|---|
| Flutter, Firebase Auth, Firestore | In use |
| Firebase Storage for pictures | Not used. Pictures are stored inside Firestore (small). Storage needs Blaze |
| Google Maps | Not used. The app uses OpenStreetMap (free). Google Maps needs billing + API key |
| Latitude / longitude on profiles | Built as opt-in, rounded to about 1 km (exact position is never stored) |
| AdMob ads | Deliberately NOT added yet: it adds a heavy dependency and must not risk the build before the core flow is confirmed on a phone. Will use test IDs only, never on emergency screens |

## 8. Release
| Requirement | Status |
|---|---|
| Security rules | Written, needs deploy + test |
| App name / ID, icon, signing key, store listing, screenshots | Not done. App ID is still `com.example.blood_connect` |
