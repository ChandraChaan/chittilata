# Security policy

Chittilata is a multiplayer game where hidden information (your hand, your role) must stay hidden. Reports about ways to see other players' cards or roles, act out of turn, change scores, or read data you shouldn't are very welcome.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting instead: go to the repository's **Security** tab and choose **Report a vulnerability**.

Include what you did, what you could see or change, and the app version (the release you installed). Reports are handled privately, and you will be credited in the changelog unless you would rather stay anonymous.

## Scope

- In scope: `firestore.rules`, Cloud Functions in `functions/`, and the Android app.
- Out of scope: the Firebase client API key in `google-services.json` / `firebase_options.dart`. It is a public identifier that ships in every Android app, not a secret. Access is controlled by security rules and server-side checks.
- Please test only against your own Firebase project or the local emulators (`npm run test:emulator`). Don't disrupt rooms other people are playing in.

## Supported versions

Only the [latest release](https://github.com/ChandraChaan/chittilata/releases/latest) receives fixes. The backend is shared, so old app builds may stop working after a fix.
