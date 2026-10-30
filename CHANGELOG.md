# Changelog

All notable changes to Chittilata. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- MIT license.
- README with demo GIF, screenshot gallery and architecture diagram; social preview image.
- `SECURITY.md` (private vulnerability reporting), `CONTRIBUTING.md`, issue and pull request templates, Dependabot configuration.

### Changed
- CI runs with a read-only token. The release workflow now correctly detects the optional Firebase service account and deletes it after use.
- Stopped tracking the downloaded Crashlytics symbol tool (`.crashlytics/`).

## [2.0.0] — 2026-10-30

### Added
- **👑 King & Queen**, a second game mode for 4–10 players, with its own lobby, settings, rules and screens:
  - Role names are written, folded, shuffled and scattered. Each player picks exactly one chit, which unfolds privately.
  - The King hunts the Queen, the Queen the next role, and so on down the chain. Wrong guesses swap roles and lose the turn. Forced resolution when only one candidate remains. Random server guesses on timeout.
  - Final-role scoring, cumulative leaderboard, rounds-as-King tie-break, round-by-round table.
  - Host settings: rounds (1–30), time per guess, points for every role, names for optional roles.
- Written rules specification and state model (`docs/KING_QUEEN_RULES.md`), a pure engine with property tests (1,050 random rounds), emulator transaction tests and privacy rule tests.
- Home screen with a mode chooser; Join with a code moved above the fold; per-mode how-to-play.
- King & Queen bots (`--mode kq`).

### Changed
- Cloud Functions now use a fractional CPU and at most 5 instances each, to stay within the regional Cloud Run CPU quota.
- Version 2.0.0 (build 3).

### Unchanged
- Movie Chits rules, dealing, picking, scoring, tie-breakers and security rules. All Movie Chits tests still pass.

## [1.0.0] — 2026-10-30

The first stable release of **Movie Chits**, the Telugu paper-slip game *Chittilu Aata*.

### Added
- **Folded-chit picking.** Movie names are written, folded, shuffled and scattered on a woven mat. Each player picks 4 chits that unfold privately, with sound and haptics. Server-authoritative: a chit can be taken once, players are capped at 4, retries are idempotent, and the deadline auto-picks.
- **Character chits.** Non-winners each pick one sealed character chit (Queen, Police, Thief…) and reveal it privately.
- Paper fold, shuffle, pick and unfold sound effects.
- Bot players (`functions/scripts/bots.mjs`) can pick chits, use `--pick-delay`, and claim deadlines like the app.
- Updated how-to-play video showing chit picking.

### Changed
- Rounds now start in a `picking` phase. The fair-deal rules, passing, scoring and tie-breakers are unchanged.
- A new server-only `rooms/{id}/secrets` document, denied to all clients by the security rules.

### Notes
- Requires the backend deployed with this version. `v1.0.0-beta.1` clients do not understand the picking phase.

## [1.0.0-beta.1] — 2026-10-30

First beta: rooms for 3–10 players, fair server-side dealing, timed passing, four-of-a-kind wins, secret characters, reveals, King & Queen ceremony with an optional tie-breaker round, match history, sound, music and vibration settings, and Crashlytics.
