# Chittilata — Privacy Policy

_Last updated: 2 November 2026._

Chittilata ("the app") is a multiplayer card game made by Chandra ("we"). This policy explains what the app collects and why.

## What we collect

| Data | Why | Where it is stored |
|---|---|---|
| **Anonymous account ID** (created automatically by Firebase Authentication; no email, phone or password) | Identifies your seat in a game so you can reconnect | Google Firebase |
| **Display name you type** (e.g. "Chandra") | Shown to the other players in your room | Firebase Cloud Firestore, inside the room |
| **Game data** (your slips, turns, scores, character cards, timestamps of your last activity in a room) | Running the game fairly on our server | Firebase Cloud Firestore |
| **Quick-chat messages** you choose to send: a preset emoji, a preset phrase or a nudge (there is no free-text chat), and when you sent it. Only your latest message is kept | Showing it to the other players in your room | Firebase Cloud Firestore, inside the room |
| **Avatar emoji** you choose (optional, from a fixed list) | Shown next to your name in rooms and groups | Firebase Cloud Firestore |
| **Push notification token** (a random ID for this app install, only if you allow notifications) | Telling you when it's your turn, or someone nudged you, while the app is closed | Firebase Cloud Firestore (readable only by our server) and Firebase Cloud Messaging |
| **Friend groups** you create or join: the group name, members' display names and avatars, and each month's points, games and King/Queen titles | Showing the group's monthly leaderboard to its members | Firebase Cloud Firestore |
| **Crash reports** (stack traces, device model, OS version, app version, a random installation ID) | Fixing crashes | Firebase Crashlytics |

We do **not** collect your contacts, location, photos, microphone, advertising ID, or payment details. The app contains **no ads** and **no analytics SDK**. Crash reports never include your name, your slips or room codes.

Your sound, vibration, notification and theme preferences, your match history, and your profile stats, levels and badges are stored **only on your phone**.

## Who can see your data

- **Other players in your room** see your display name, avatar, ready/online status, scores, your quick-chat messages and nudges, and, after each round ends, that round's slips and character cards. People who join a game after it started can watch the same public table (never anyone's private slips or role).
- **Quick match (Play online)** puts you at a table with people you may not know. They see the same things as above. Names containing abusive words are replaced with "Player N" at public tables, and chat is preset-only.
- **Members of your friend groups** see your display name, avatar and monthly results in that group.
- **Your private slips** during a round are visible only to you, enforced by our server's security rules. The host can't see them either.
- **Google (Firebase)** processes the data on our behalf as a service provider. See https://firebase.google.com/support/privacy.
- We do not sell or share your data with anyone else.

## How long we keep it

- Rooms close after 24 hours without activity, and all data in a closed room (names, slips, scores, chat messages, logs) is **permanently deleted 7 days after it closes**.
- Friend groups are kept until their last member leaves; then the group and its seasons are deleted.
- Your push token is deleted when you turn notifications off in Settings, or when Firebase reports it no longer works (for example after uninstalling).
- Crash reports are kept by Firebase Crashlytics for 90 days.
- Your anonymous account ID stays until you uninstall the app or clear its data.

## Your choices

- Use any display name you like. It doesn't have to be your real name.
- Leaving a room removes you from it. Leaving a group removes you from it. Uninstalling the app deletes everything stored on your phone.
- Notifications are optional: Android asks before any are shown, and Settings has a switch.
- To ask for deletion of server data before the automatic deletion, contact us at the address below.

## Children

Chittilata is a family game, but it is not directed at children under 13 and does not knowingly collect personal information from them.

## Security

All traffic is encrypted (HTTPS/TLS). Game rules and scoring run on our server, and the database only allows each player to read what they are entitled to.

## Contact

Chandra — dumpalachandu@gmail.com
