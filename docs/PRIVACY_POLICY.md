# ChitPlay (Chittilata) — Privacy Policy

_Last updated: 19 November 2026._

ChitPlay, formerly Chittilata ("the app"), is a multiplayer card game made by Chandra ("we"). This policy explains what the app collects and why.

## What we collect

| Data | Why | Where it is stored |
|---|---|---|
| **Account ID** (created automatically by Firebase Authentication; as a guest there is no email, phone or password) | Identifies your seat in a game so you can reconnect | Google Firebase |
| **Google account email address and name** — only if you choose *Sign in with Google*, which is optional | Linking your profile to your Google account so it follows you to other phones and reinstalls. Shown only to you, in the app | Firebase Authentication |
| **Cloud profile** — only while signed in with Google: your display name, avatar, level and XP, stats, badges, and match history (results of your finished games, including the display names of the players at the table) | Restoring your progress on any phone where you sign in | Firebase Cloud Firestore (readable only by you) |
| **Display name you type** (e.g. "Chandra") | Shown to the other players in your room | Firebase Cloud Firestore, inside the room |
| **Game data** (your slips, turns, scores, character cards, timestamps of your last activity in a room) | Running the game fairly on our server | Firebase Cloud Firestore |
| **Chat messages** you choose to send: a preset emoji, a preset phrase, a nudge, or (in rooms of friends, for seated players) a short typed message of up to 80 characters, and when you sent it. The room's chat history is kept with the room | Showing it to the other players in your room | Firebase Cloud Firestore, inside the room |
| **Reports** you send about another player: their anonymous ID and display name, the room, the reported message (if any) and the reason you picked | Reviewing abuse and keeping rooms safe | Firebase Cloud Firestore (readable only by the developer) |
| **Avatar emoji** you choose (optional, from a fixed list) | Shown next to your name in rooms and groups | Firebase Cloud Firestore |
| **Push notification token** (a random ID for this app install, only if you allow notifications) | Telling you when it's your turn, or someone nudged you, while the app is closed | Firebase Cloud Firestore (readable only by our server) and Firebase Cloud Messaging |
| **Friend groups** you create or join: the group name, members' display names and avatars, and each month's points, games and King/Queen titles | Showing the group's monthly leaderboard to its members | Firebase Cloud Firestore |
| **Crash reports** (stack traces, device model, OS version, app version, a random installation ID) | Fixing crashes | Firebase Crashlytics |

When you invite a friend with *Contact*, Android's own picker gives the app only the one phone number you choose. It is used on your phone to open WhatsApp or your messaging app, and is never stored or sent to us. We do **not** collect your contacts, location, photos, microphone, advertising ID, or payment details. The app contains **no ads** and **no analytics SDK**. Crash reports never include your name, your slips or room codes.

Your sound, vibration, notification and theme preferences are stored **only on your phone**. As a guest, your match history and your profile stats, levels and badges are also stored only on your phone. If you sign in with Google, they are also saved to your cloud profile so they follow you.

## Who can see your data

- **Other players in your room** see your display name, avatar, ready/online status, scores, your quick-chat messages and nudges, and, after each round ends, that round's slips and character cards. People who join a game after it started can watch the same public table (never anyone's private slips or role).
- **Quick match (Play online)** puts you at a table with people you may not know. They see the same things as above. Names containing abusive words are replaced with "Player N" at public tables, and chat there is preset-only (no typed messages).
- **Members of your friend groups** see your display name, avatar and monthly results in that group.
- **Your private slips** during a round are visible only to you, enforced by our server's security rules. The host can't see them either.
- **Google (Firebase)** processes the data on our behalf as a service provider. See https://firebase.google.com/support/privacy.
- We do not sell or share your data with anyone else.

## How long we keep it

- Rooms close after 24 hours without activity, and all data in a closed room (names, slips, scores, chat messages, logs) is **permanently deleted 7 days after it closes**.
- Friend groups are kept until their last member leaves; then the group and its seasons are deleted.
- Your push token is deleted when you turn notifications off in Settings, or when Firebase reports it no longer works (for example after uninstalling).
- Crash reports are kept by Firebase Crashlytics for 90 days.
- Reports are kept for up to 1 year, then deleted.
- As a guest, your account ID stays until you uninstall the app or clear its data.
- If you sign in with Google, your account and cloud profile are kept until you delete them (see below). Signing out keeps them with your Google account for when you sign in again.

## Your choices

- In the room chat, long-press a message (or use the chat's ⋮ menu) to **mute** a player on your phone or **report** them. Settings → *Typed chat messages* hides everything other players type. Typed messages are filtered for abusive words on every phone.
- Use any display name you like. It doesn't have to be your real name.
- Leaving a room removes you from it. Leaving a group removes you from it. Uninstalling the app deletes everything stored on your phone.
- Notifications are optional: Android asks before any are shown, and Settings has a switch.
- Signing in with Google is optional. Everything in the game works as a guest.

## Deleting your account and data

- **In the app:** Settings → *Delete my account and data* (also on your profile when signed in). This deletes your sign-in and cloud profile, removes your push token, takes you out of your rooms and friend groups (removing your name from the groups), and clears your profile from the phone. It works the same for guests.
- **Without the app:** see https://chittilata-game.web.app/delete-account, or email us at the address below from the Google account you signed in with. We delete it within 30 days.
- Some data is kept for a limited time after deletion: rooms you played in keep past results, including your display name, until they are deleted automatically (at most 24 hours of inactivity plus 7 days); reports you sent are kept for up to 1 year; crash reports for 90 days.

## Children

Chittilata is a family game, but it is not directed at children under 13 and does not knowingly collect personal information from them.

## Security

All traffic is encrypted (HTTPS/TLS). Game rules and scoring run on our server, and the database only allows each player to read what they are entitled to.

## Contact

Chandra — dumpalachandu@gmail.com
