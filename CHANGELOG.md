# Changelog

All notable changes to Chittilata. Versions follow [Semantic Versioning](https://semver.org/).

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
