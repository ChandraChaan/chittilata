# Chittilata (చిట్టిలాట)

Traditional Telugu paper-chit games as a secure, real-time multiplayer Android app. Everyone plays on their own phone. Two game modes:

- 🎬 **Movie Chits** (3–10 players): *Chittilu Aata*. Pick folded movie chits, pass slips around a random circle, race to collect four of a kind, pick secret character chits, and crown a **King** and **Queen** after several rounds.
- 👑 **King & Queen** (4–10 players): each player picks one folded role chit. The King must find the Queen, the Queen the next role, and so on down the chain. Wrong guesses swap roles, and everyone scores their final role.

<p>
  <img src="docs/store/screenshots/03-your-turn.png" width="200" alt="Your turn">
  <img src="docs/store/screenshots/04-winner-and-character.png" width="200" alt="Winner and secret character">
  <img src="docs/store/screenshots/06-king-and-queen.png" width="200" alt="King and Queen">
</p>

- **Players:** [How to play](docs/HOW_TO_PLAY.md) · [Movie Chits rules](docs/GAME_RULES.md) · [King & Queen rules](docs/KING_QUEEN_RULES.md) · [Video walkthrough](docs/media/chittilata-how-to-play.mp4)
- **Developers:** [Architecture & security](docs/ARCHITECTURE.md) · [Release checklist](docs/RELEASE_CHECKLIST.md) · [Changelog](CHANGELOG.md)
- **Store:** [Listing](docs/store/LISTING.md) · [Data Safety](docs/store/DATA_SAFETY.md) · [Privacy policy draft](docs/PRIVACY_POLICY.md)

## Download a test build

Signed APKs are attached to [GitHub Releases](https://github.com/ChandraChaan/chittilata/releases). Most phones need `chittilata-<version>-arm64-v8a.apk`. If unsure, use the `universal` APK. Beta testers can also be invited through Firebase App Distribution.

## Stack

| Layer | Tech |
|---|---|
| App | Flutter 3.44 / Dart 3.12, Android only (minSdk 24) |
| Backend | Firebase project `chittilata-game` (asia-south1): anonymous Auth, Cloud Firestore, Cloud Functions (Node 22, TypeScript) |
| Integrity | All game actions are server-side transactions with turn ids, idempotency keys and server deadlines. Firestore rules give each player read access to only their own hand |
| Ops | Crashlytics (Dart + native/NDK), App Distribution, GitHub Actions |

## Develop

```bash
flutter pub get
flutter run                      # talks to the deployed Firebase backend
```

```bash
cd functions && npm ci
npm test                         # game-engine unit tests
JAVA_HOME=/opt/homebrew/opt/openjdk@21 npm run test:emulator   # security rules + transactions on the Firestore emulator
```

```bash
flutter analyze && flutter test  # Flutter unit + widget tests
```

### Play with bots

`functions/scripts/bots.mjs` adds bot players that use the same callables and rules as the app:

```bash
cd functions
node scripts/bots.mjs --code ABC234 --count 3              # join your room from the app
node scripts/bots.mjs --create --count 4 --rounds 2        # headless full game + card-conservation checks
node scripts/bots.mjs --create --mode kq --count 5 --rounds 2   # headless King & Queen game
node scripts/bots.mjs --mode kq --code ABC234 --count 3    # bots join your King & Queen room
```

### Deploy backend

```bash
firebase deploy --only functions,firestore:rules
```

## Project layout

```
lib/                 Flutter app (core/ theme+services, data/ models+repository, game/ controller, ui/)
functions/src/engine Pure TypeScript game rules (deal, exchange, characters, scoring, catalogue, kingqueen)
functions/src/game   Firestore transactions for each callable (ops.ts Movie Chits + lobby, kq.ts King & Queen)
firestore.rules      Least-privilege security rules
test/, functions/test  Flutter tests, engine tests, emulator security/integration tests
tool/                Sound synthesis + brand sources
docs/                Rules, architecture, store assets, video
```

Secrets are never committed: the release keystore lives outside the repo and `android/key.properties` is git-ignored. `google-services.json` and `firebase_options.dart` contain public client identifiers, not secrets.
