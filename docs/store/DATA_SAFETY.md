# Google Play Data Safety — prepared answers

These answers are based on the code in this repository (Firebase Auth anonymous, Cloud Firestore, Cloud Functions, Crashlytics + NDK; no ads or analytics SDKs). Re-check them if you add SDKs.

**Does your app collect or share any of the required user data types?** Yes.
**Is all of the user data collected by your app encrypted in transit?** Yes (HTTPS/TLS via Firebase SDKs).
**Do you provide a way for users to request that their data is deleted?** Yes. Rooms auto-delete 7 days after closing, and users can request earlier deletion by email at the address in the privacy policy.

| Data type (Play category) | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| Personal info → **Name** (player-chosen display name) | Yes | No | Required to play | App functionality |
| Personal info → **User IDs** (Firebase anonymous UID) | Yes | No | Required | App functionality |
| App activity → **Other actions** (game moves, scores) | Yes | No | Required | App functionality |
| Messages → **Other in-app messages** (preset emojis, phrases and nudges; no free text) | Yes | No | Optional | App functionality |
| App info & performance → **Crash logs** | Yes | No | Required | Analytics (crash diagnostics) |
| App info & performance → **Diagnostics** (device model, OS, app version) | Yes | No | Required | Analytics (crash diagnostics) |
| Device or other IDs → **Firebase installation ID** | Yes | No | Required | Analytics (crash diagnostics) |

Not collected: location, contacts, photos/videos, audio, files, calendar, messages, health, financial info, web browsing, advertising ID.

"Shared" means transferred to a third party. Firebase acts as a **service provider** processing data on our behalf, which Play does not count as sharing.

Is data processed ephemerally? No. Room data persists until deletion as described above.
