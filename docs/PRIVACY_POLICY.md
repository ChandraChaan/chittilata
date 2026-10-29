# Chittilata — Privacy Policy

_Last updated: 30 October 2026. This is a draft prepared for the developer; review it and publish it at a public URL (for example GitHub Pages) before submitting to Google Play._

Chittilata ("the app") is a multiplayer card game made by Chandra ("we"). This policy explains what the app collects and why.

## What we collect

| Data | Why | Where it is stored |
|---|---|---|
| **Anonymous account ID** (created automatically by Firebase Authentication; no email, phone or password) | Identifies your seat in a game so you can reconnect | Google Firebase |
| **Display name you type** (e.g. "Chandra") | Shown to the other players in your room | Firebase Cloud Firestore, inside the room |
| **Game data** (your slips, turns, scores, character cards, timestamps of your last activity in a room) | Running the game fairly on our server | Firebase Cloud Firestore |
| **Crash reports** (stack traces, device model, OS version, app version, a random installation ID) | Fixing crashes | Firebase Crashlytics |

We do **not** collect your contacts, location, photos, microphone, advertising ID, or payment details. The app contains **no ads** and **no analytics SDK**. Crash reports never include your name, your slips or room codes.

Your sound, vibration and theme preferences and your match history are stored **only on your phone**.

## Who can see your data

- **Other players in your room** see your display name, ready/online status, scores and, after each round ends, that round's slips and character cards.
- **Your private slips** during a round are visible only to you, enforced by our server's security rules. The host can't see them either.
- **Google (Firebase)** processes the data on our behalf as a service provider. See https://firebase.google.com/support/privacy.
- We do not sell or share your data with anyone else.

## How long we keep it

- Rooms close after 24 hours without activity, and all data in a closed room (names, slips, scores, logs) is **permanently deleted 7 days after it closes**.
- Crash reports are kept by Firebase Crashlytics for 90 days.
- Your anonymous account ID stays until you uninstall the app or clear its data.

## Your choices

- Use any display name you like. It doesn't have to be your real name.
- Leaving a room removes you from it. Uninstalling the app deletes everything stored on your phone.
- To ask for deletion of server data before the automatic deletion, contact us at the address below.

## Children

Chittilata is a family game, but it is not directed at children under 13 and does not knowingly collect personal information from them.

## Security

All traffic is encrypted (HTTPS/TLS). Game rules and scoring run on our server, and the database only allows each player to read what they are entitled to.

## Contact

Chandra — **[add a contact email before publishing]**
