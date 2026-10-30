# Contributing to Chittilata

Thanks for helping! Bug reports, rule variants from your family's version of the game, new movie packs and code are all welcome.

## Before you start

- For anything bigger than a small fix, please open an issue first so we can agree on the approach.
- Game rules are specified in [docs/GAME_RULES.md](docs/GAME_RULES.md) and [docs/KING_QUEEN_RULES.md](docs/KING_QUEEN_RULES.md). If a change alters gameplay, update the spec in the same pull request.

## Setup

```bash
flutter pub get
cd functions && npm ci
```

The Firestore emulator tests need Java 21.

## Checks to run before opening a pull request

```bash
dart format lib test && flutter analyze && flutter test
cd functions && npm run build && npm test && npm run test:emulator
```

CI runs the same checks on every pull request.

## Ground rules

- **Server-authoritative.** Clients must never write game state directly. New moves go through a callable in `functions/src/game` running inside a Firestore transaction, with the rules themselves in the pure engine (`functions/src/engine`) and unit tests to match.
- **Hidden stays hidden.** Never put a player's cards or role in a document other players can read, and never log them. If you touch `firestore.rules`, add or extend a test in `functions/test/integration/rules.test.ts`.
- **No secrets in the repo.** Keystores, `key.properties`, service-account JSON and `.env` files are git-ignored. Keep it that way.
- Don't weaken or delete tests to make a build pass.
- Use small commits with [Conventional Commit](https://www.conventionalcommits.org/) messages (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Adding movie names

Movie packs live in `functions/src/engine/catalogue.ts`. Use names that are easy to recognise and distinct from each other, avoid duplicates, and run `npm test`, which checks that every category has enough names for 10 players.
