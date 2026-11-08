# Supervisor feedback (handwritten note) - status

> Written without being able to run Flutter. Items marked "Built" are written in code and still need a test on a real phone.

| # | Supervisor note | Status | What was done / what to know |
|---|---|---|---|
| 1 | Chat system is not there | **Built** | New chat screen between donor and receiver. It opens from the request cards (button "Chat with receiver" for the donor, "Chat with donor" in the receiver's Alerts) once the donor has accepted. Only the two people can read or write (Firestore rules + 4 new rules tests). Text only, max 1000 characters. The chat closes when the request is completed. Report/Block is in the chat menu. No push notification for new chat messages yet. |
| 2 | Communication between donor and finder | **Built** | Chat + phone numbers shared after acceptance (already built). |
| 3 | App icon differs from the actual app / make app icon and logo the same | **Built** | One logo (white blood drop with a heart on the app's red gradient) is now used for the Android icon (normal and adaptive), the iOS icon set, the web favicon and the splash screen. A 512x512 Play Store icon is provided. Uninstall the old app before installing to see the new icon. |
| 4 | Alerts tab is not working (Notification Preference) | **Fixed** | Cause: the "Notification Preferences" card looked tappable but did nothing. It is now a working switch (same setting as Profile > Notifications) in both donor and receiver Alerts tabs. It really turns live alerts and push on/off. Also fixed: raw error text on the Alerts tab, and the donor card always showing "1 unit". |
| 5 | "Blood group & edit profile are some..." | **Unclear** | The sentence is cut off in the photo. Need the exact words from the supervisor. |
| 6 | Language feature is not working | **Built (59 languages)** | Before: the choice was only saved. Now the app switches language: English and Urdu are translated by hand (about 540 texts, right-to-left for Urdu); 57 more languages are machine-translated on the phone (Google ML Kit, one-time download of about 30 MB per language, needs internet for that download). Not translated yet: long legal paragraphs, texts that contain names or numbers. The language applies after login. A native Urdu speaker should review the wording. |
