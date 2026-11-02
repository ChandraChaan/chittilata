# Changelog

All notable changes to Chittilata. Versions follow [Semantic Versioning](https://semver.org/).

## [2.3.1] — 2026-11-03

### Fixed
- **The last chits not responding.** After every pick, a full-screen "You picked…" reveal covered the mat for about two seconds, and a tap during it only skipped the reveal. The slip now unfolds in a small card above your tray that taps go straight through, so quick picks always land. The "Time's up!" banner also lets taps through.

### Changed
- **Picking chits has a 1-minute timer, then picks for you.** Movie chits, character chits and King & Queen role chits: when the minute is up, anything not yet picked is picked at random, so a round never waits on someone who walked away. The last 5 seconds tick and the screen says "picked for you in Ns". (Passing and guessing still never play for you automatically; others can still nudge or "Play for" a late player.)

## [2.3.0] — 2026-11-02

### Added
- **🎭 Movie Dumb Charades**, a third game mode for people playing together: one player secretly gets a movie and acts it out, everyone else picks it from six titles. Fastest right guess scores most; the actor scores too.
- **🤖 Practice with bots** in Movie Chits and King & Queen, and an *Add a bot* button for hosts. Bots think for a moment, then pick, pass and guess on their own.
- **🌐 Play online (quick match).** Get matched into a public table with other players; it starts when everyone is ready or after 40 seconds, and bots fill empty seats. Names with abusive words are hidden from strangers.
- **📨 Invite links.** *Invite friends* shares a link (WhatsApp, any app) that opens the app straight into the room, or the Play Store page if it isn't installed. Group invites work the same way.
- **🔔 Notifications.** "Your turn", new rounds, nudges and tie-breaker votes reach you when the app is closed. Never when you're looking at the game. Switch them off in Settings.
- **👀 Watch and rejoin.** Joining a game that already started lets you watch (and send emojis). After reinstalling or changing phones, tap *I am …* on your old seat; once the host approves, you continue with your score from the next round. Watchers get seats when the game is played again.
- **😀 Profiles.** Pick an avatar emoji everyone sees, earn XP and levels, track your stats, and unlock 14 badges.
- **👥 Friend groups.** Save your regular circle, play games that count for the group, and climb a monthly leaderboard with a champion each month.
- **🪔 Festival themes** for Sankranti, Ugadi and Diwali (kites, mango-leaf toranam, glowing diyas), automatic around each festival or picked in Settings.

### Changed
- Home has a profile chip, groups, Play online and a third game.
- Lobbies show the group a game counts for, quick-match countdowns, and bots.

## [2.2.0] — 2026-11-02

### Added
- **New sound design.** Every sound is newly made for the app: a crisp 3D-button click, softer taps and back clicks, whooshes when sheets and dialogs open, a battle-start "boom" when the game begins, chimes when friends join, chat pops, a knock-knock nudge, urgent ticks in the last 3 seconds, coin sounds and a bigger victory fanfare.
- **Music.** A festive menu theme (tabla, bansuri-style flute, santoor sparkle) and a lighter in-game groove, crossfading between menus and games. On by default; turn it off in Settings. It pauses when the app goes to the background and plays alongside other apps' audio instead of stopping it.
- **Haptics.** Patterns for game start, your turn, wins (a rising roll), and "not allowed" (double thump), on top of the existing taps and buzzes.
- **Update checks.** If `config/app` in Firestore sets `minBuild` above the installed build, the app shows a full-screen "Update required" page; `latestBuild` shows a dismissible "New version available" card. Update uses Google Play's in-app update, or opens the store (or `updateUrl`).
- Layout tests: every screen is rendered on a small phone, a 16:9 phone, a tablet and at 130%, 160% and 200% text size, and must not overflow.

### Changed
- **New look.** Deeper night-sky background with soft glows and stars; chunky gold 3D buttons that sink when pressed; glassy panels; gold logo title; gold-edged dialogs and sheets.
- Tapping a button that isn't available yet (e.g. Start before everyone is ready) gives a soft "not yet" buzz instead of nothing. Errors from the server do too.
- On tablets and foldables, screens stay a comfortable width in the middle instead of stretching edge to edge.

### Fixed
- Text and buttons that ran off the screen with large system fonts or on small phones: the round-results rows, tie-breaker rows, the round intro, the late-player banner, the lobby header, the how-to-play pages and the name strip on the slip table.

## [2.1.1] — 2026-11-02

### Fixed
- **Top crash in 2.0.0** (549 crash reports from 9 players): "The error handler of Future.catchError must return a value of the future's type". Fire-and-forget server calls such as reveal, timeouts and tie-breaker votes returned the callable's `Future<Map>` from `Future<void>` methods, so whenever one failed (for example, two phones racing to reveal) the error handler itself threw, again and again. They now return a real `Future<void>`, and a test guards it.
- A crash when tapping **Next** in the how-to-play pages on phones with animations turned off.
- **The last chits jumped away from your finger.** When the pick timer ran out, the "Time's up!" banner took space at the bottom, the mat shrank and every chit moved up, so taps on the last 2–3 chits landed on empty mat. The banner (and the offline banner) now float over the top of the screen, so the mat and your hand never move.

### Added
- Settings → About shows the installed app version, so you can check which build a phone has.

## [2.1.0] — 2026-11-01

### Added
- **💬 Quick chat**: one-tap emojis and preset phrases in Telugu and English (త్వరగా! ⏰, అయ్యో! 😩, Good game! 🤝…) float up on everyone's screen, in the lobby and during play. Presets only: no free text to moderate.
- **👋 Nudge**: buzz a slow player's phone. Nudges aimed at you show big and vibrate.
- Late-player banner: "Waiting for Ravi ⏰" → "Ravi is thinking hard 🤔" → "Ravi fell asleep 😴", or "offline 📵".
- Debug and profile builds can play against local Firebase emulators (`--dart-define=USE_EMULATOR=true`); bots can chat and nudge (`--chat`).
- MIT license.
- README with demo GIF, screenshot gallery and architecture diagram; social preview image.
- `SECURITY.md` (private vulnerability reporting), `CONTRIBUTING.md`, issue and pull request templates, Dependabot configuration.

### Changed
- **Nothing is played automatically when time runs out**: no auto-pass, auto-pick or auto-guess. The late player's phone buzzes (and again every 10 s) with a shaking "Time's up!" banner, and they can still play. Another player can **Play for** them only 45 s after the deadline, or straight away if their phone is offline; the server enforces both.
- CI runs with a read-only token. The release workflow now correctly detects the optional Firebase service account and deletes it after use.
- Stopped tracking the downloaded Crashlytics symbol tool (`.crashlytics/`).

### Fixed
- Folded chits that didn't respond to taps, especially the last few on the mat: tilted corners were outside the tap area, a neighbour's invisible margin could take the tap, chits near the edge poked off the table, and the 25 s pick timer could auto-pick the chits you were reaching for. Taps now pick the chit drawn under your finger, or the nearest one within reach.

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
