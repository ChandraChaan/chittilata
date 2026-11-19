# Google Play Data Safety — prepared answers

These answers are based on the code in this repository (Firebase Auth anonymous plus optional Google sign-in, Cloud Firestore, Cloud Functions, Cloud Messaging, Crashlytics + NDK, Google Play In-App Updates; no ads or analytics SDKs). Re-check them if you add SDKs.

**Does your app collect or share any of the required user data types?** Yes.
**Is all of the user data collected by your app encrypted in transit?** Yes (HTTPS/TLS via Firebase SDKs).
**Do you provide a way for users to request that their data is deleted?** Yes. In the app: Settings → *Delete my account and data* (deletes the account, cloud profile and push token, and leaves rooms and groups). Rooms auto-delete 7 days after closing.

**Account creation (Data safety → Data deletion / App access):**
- *Does your app allow users to create an account?* Yes, optionally. Method: **OAuth** (Sign in with Google). Guests play without an account (anonymous Firebase ID, no login).
- *Delete account URL:* **https://chittilata-game.web.app/delete-account**
- *Do you provide a way for users to request that some or all of their data is deleted, without requiring them to delete their account?* Yes: signing out clears the profile from the phone, leaving a room or group removes you from it, and rooms auto-delete.
- **App access:** all functionality is available without signing in (sign-in is optional), so no test credentials are needed.

| Data type (Play category) | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| Personal info → **Name** (player-chosen display name; plus the Google account name if the player signs in with Google) | Yes | No | Display name required to play; Google name optional | App functionality, Account management |
| Personal info → **Email address** (Google account email, only with the optional Google sign-in) | Yes | No | Optional | App functionality, Account management |
| Personal info → **User IDs** (Firebase UID, anonymous or linked to Google) | Yes | No | Required | App functionality, Account management |
| App activity → **Other actions** (game moves, scores; with Google sign-in also the cloud profile: level/XP, stats, badges, match history) | Yes | No | Required (cloud profile optional) | App functionality |
| Messages → **Other in-app messages** (preset emojis, phrases and nudges, plus short typed messages of up to 80 characters between seated players in rooms of friends; chat history kept with the room) | Yes | No | Optional | App functionality |
| App activity → **Other user-generated content** (abuse reports: reported player's ID and name, the message, the reason) | Yes | No | Optional | App functionality (safety) |
| App activity → **Other user-generated content** (avatar emoji, friend group names and monthly results) | Yes | No | Optional | App functionality |
| Device or other IDs → **Push notification token** (Firebase Cloud Messaging) | Yes | No | Optional (only if notifications are allowed) | App functionality |
| App info & performance → **Crash logs** | Yes | No | Required | Analytics (crash diagnostics) |
| App info & performance → **Diagnostics** (device model, OS, app version) | Yes | No | Required | Analytics (crash diagnostics) |
| Device or other IDs → **Firebase installation ID** | Yes | No | Required | Analytics (crash diagnostics) |

Not collected: location, contacts (the *Contact* invite uses Android's system picker; the one number chosen is used on the device only to open WhatsApp/SMS and never leaves it, so it is not "collected"), photos/videos, audio, files, calendar, messages, health, financial info, web browsing, advertising ID.

"Shared" means transferred to a third party. Firebase acts as a **service provider** processing data on our behalf, which Play does not count as sharing.

Is data processed ephemerally? No. Room data persists until deletion as described above.
