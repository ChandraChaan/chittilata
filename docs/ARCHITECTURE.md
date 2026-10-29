# Chittilata architecture

## Overview

```
Android app (Flutter)                Firebase project: chittilata-game (asia-south1)
┌──────────────────────────┐         ┌──────────────────────────────────────────────┐
│ UI screens & widgets      │ reads   │ Cloud Firestore                               │
│ RoomController            │◀────────│  rooms/{id}            public room state      │
│  (streams, timers,        │         │  rooms/{id}/rounds/*   public round state     │
│   presence, claims)       │         │  rooms/{id}/hands/{uid} PRIVATE hand+character│
│ FirebaseGameRepository    │ writes  │  rooms/{id}/presence/* heartbeat (client)     │
│                           │────────▶│  rooms/{id}/audit/*    server-only log        │
│                           │ calls   │  roomCodes/{code}      server-only index      │
│                           │────────▶│ Cloud Functions (callables, Node 22, TS)      │
└──────────────────────────┘         │  game engine (pure TS, unit-tested)           │
                                      └──────────────────────────────────────────────┘
```

**The server is the only authority.** Clients never write game state. Every action (create, join, ready, settings, start, pass, timeout, reveal, next round, play again, leave) is an authenticated callable Cloud Function. Each one runs inside a Firestore **transaction**, validates the request against the authoritative state, and writes the result. Clients only *read* what they are entitled to, plus write their own presence heartbeat.

## Code layout

| Path | Responsibility |
|---|---|
| `functions/src/engine/` | Pure game rules: catalogue, deal, exchange, characters, scoring, settings. No Firebase. |
| `functions/src/game/ops.ts` | Firestore transactions that apply the engine (one function per callable). |
| `functions/src/index.ts` | Callable wrappers, error mapping, `serverNow`, scheduled room expiry. |
| `firestore.rules` | Least-privilege read rules; all game writes denied to clients. |
| `lib/data/` | Firestore document models and `GameRepository` (Firebase and fake implementations). |
| `lib/game/room_controller.dart` | Live subscriptions, server-aligned clock, timeout/reveal claims, feedback triggers. |
| `lib/ui/` | Screens, design-system widgets, rules content. |
| `lib/core/` | Theme tokens, preferences, sound/haptics. |
| `functions/scripts/bots.mjs` | Bot players for end-to-end testing against the real backend. |
| `tool/` | Sound synthesis and brand-asset sources. |

## Data model and privacy

| Document | Who can read | Contents |
|---|---|---|
| `rooms/{id}` | members (`memberUids`) | code, host, status, players, settings, totals, final standings |
| `rounds/{key}` | members | order, current/next player, turn id, server deadlines, movie names, hand **sizes**, winner; **hands, characters and scores appear only after reveal** |
| `hands/{uid}` | **that player only** | their cards (with stable random card ids), incoming card id, secret character |
| `presence/{uid}` | members | `lastSeen` (must equal server time), `state` |
| `secrets/{key}` | nobody (server only) | each player's not-yet-picked slips, chit→card bindings, sealed character chits |
| `audit/*`, `roomCodes/*` | nobody (server only) | debug log with card details; code → room index |

Because card ids are random per round and never appear in public documents, watching the public round state reveals nothing about which slip moved.

## Integrity mechanisms

- **Turn ids.** Every pass carries the `turnId` it was made for. A stale or competing request fails the check, so two simultaneous passes cannot both apply.
- **Idempotency keys.** Every pass carries a `requestId`. If a retried request arrives after it already succeeded, it returns `duplicate: true` and changes nothing.
- **Transactions.** Room, round and both affected hands are read and written atomically, so concurrent requests serialize.
- **Exactly-once scoring.** Movie-win points are added in the same transaction as the `exchange → characters` status change, and character points with the `characters → revealed` change. Retries can't award points twice. Round scores are stored per round (`rounds/*.scores`), separately from cumulative `totals`.
- **Server deadlines.** `turnDeadline` and `introEndsAt` are server timestamps. Passes after `deadline + 1s` are rejected. A timeout can only be applied after that point, by any member calling `claimTimeout`. The player after the stuck one asks first and others stagger, so the game keeps moving even if the stuck phone is offline. Clients align their countdown using `serverNow`, which every callable response includes.
- **Deal validation.** `validateDeal` re-checks every opening deal (counts, uniqueness, diversity, no 3-of-a-kind) before a round starts.
- **Fair randomness.** Shuffles, deals, circle order, names and characters use Node's `crypto.randomInt` with Fisher–Yates.

## Picking folded chits

A round starts in `picking`. `startRoundTx` deals fair hands with `dealHands` (unchanged rules) and stores each player's hand, shuffled, in `secrets/{key}.deal`. The public round only gets `chits` (4N opaque ids), `picks` (chit → uid), `pickOpensAt` (now + 4 s, the length of the create/fold/shuffle/scatter animation) and `pickDeadline` (+25 s). Hands start empty.

- `pickChit` (transaction): the caller must be in the round, picking must be open, the chit must exist and be free, and the caller must hold fewer than 4. The chit is bound to the next slip of **the caller's own dealt hand**, so the fair-deal guarantees always hold no matter what is picked. A retry of the same chit by the same player returns the same slip (`duplicate: true`). A chit already taken fails with `already-exists`.
- `autoPickChits` (any member, after deadline + grace) fills the remaining slots with random free chits.
- When all 4N chits are picked, the round moves to `exchange`, with `introEndsAt` = now + 5 s.

**Character chits.** When someone wins, the server takes the first N−1 configured characters, shuffles them, seals one into each chit (`secrets.characters`) and publishes only `charChits`, `charPickOpensAt` (now + 4 s) and `charPickDeadline` (+20 s). `pickCharacter` lets each non-winner take exactly one chit, and the character inside is what they get. `autoPickCharacters` finishes after the deadline. `revealAt` is set only when every character is picked, and `revealRound` refuses before that.

Chit positions on the mat come from a seeded layout (`chitLayout(roundKey)`), so every phone shows the same table. During the client-side ceremony all chits collapse into one pile before scattering, so nobody can track a chit from its slip.

## Tie-breaker

When the last round is revealed, `titleTie` checks the final standings. If players share **King** (or, failing that, **Queen**) and none of them has left, the room moves to `tiebreakVote`, with `room.tiebreak = {title, uids, votes, deadline, stage: "vote"}`.

- `tiebreakVote` (tied players only): any "no" means `finished` with shared titles (`stage: "declined"`). When everyone has said "yes", a round with `tiebreak: true` is dealt to the tied players only (2-player deals are 2+2), all in the same transaction.
- `resolveTiebreakVote` (any member, after the deadline): silence counts as "no".
- During a tie-breaker round, win and character points are **not** added to `totals`/`movieWins`. On reveal they are stored as `room.tiebreakScores`, and the ranking uses them as the third key (after total and movie wins). Then `stage` becomes `"done"`.
- If a tied player leaves during the vote or the round, `stage` becomes `"cancelled"` and the titles stay shared.

## King & Queen mode

Rooms carry `mode: "movie" | "kingQueen"` (missing means movie, for older rooms) and `kqSettings` (rounds, turnSeconds, role catalogue). Rules and the state model are in [KING_QUEEN_RULES.md](KING_QUEEN_RULES.md). The pure engine is `functions/src/engine/kingqueen.ts` and the transactions are in `functions/src/game/kq.ts`.

| Document | Who can read | Contents |
|---|---|---|
| `rooms/{id}/kqRounds/{key}` | members | players, chain names/points, chit ids, picks, step, guesser, locked (uid → final role), excluded, turnId, deadlines, guess history; `revealedRoles` + `scores` **only after the round ends** |
| `rooms/{id}/kqRoles/{uid}` | **that player only** | their current role (updated privately when a wrong guess swaps it) |
| `rooms/{id}/secrets/{key}` | nobody | sealed chit → role map and the authoritative uid → role map |

- `kqPickChit` / `kqAutoPick`: one chit per player, one player per chit, transactional and idempotent. When the last chit is taken, the King is announced and `guessing` starts (`guessOpensAt` = now + 4 s).
- `kqGuess`: only the current guesser, with the current `turnId`, before the deadline, at a current candidate. `requestId` replay protection. Applies the engine transition, including forced resolutions, writes only the changed players' `kqRoles`, and when the round ends reveals roles and scores exactly once (guarded by the status change), adding totals and `kingWins`.
- `kqClaimTimeout`: any member, after deadline + grace. The server makes a uniformly random guess for the guesser.
- Leaving mid-round voids it. Fewer than 4 players ends the game. Final ranking uses `kingWins` as the second key, and there is no tie-breaker round.
- Movie Chits code paths are unchanged. `createRoom` defaults to `movie`, and King & Queen callables refuse non-King & Queen rooms.

**Capacity.** All callables run with `cpu: "gcf_gen1"` (fractional vCPU at 256 MiB) and `maxInstances: 5`, which keeps the project inside the regional Cloud Run CPU quota.

## Timeout and reveal policy

Clients run a 250 ms ticker for the UI. When a deadline has passed (plus grace and stagger), the client calls `claimTimeout(turnId)`, and the server checks the time itself. The character reveal works the same way after `revealAt`, and the host can also reveal early.

## Reliability

- Anonymous Firebase Auth keeps a stable uid per install, so reopening the app resumes the same seat. The last room id is stored locally and reopened on launch.
- Firestore snapshots of metadata drive the "Reconnecting…" banner. Presence heartbeats every 20 s mark players online, away (backgrounded) or offline.
- `hand.roundKey` must match the round on screen, so a stale hand is never shown.
- A scheduled function closes rooms idle for 24 h and frees their codes.

## Crash reporting

`main.dart` routes Flutter framework errors and uncaught async errors to Crashlytics. Collection is on in release builds only. `firebase-crashlytics-ndk` captures native crashes. R8 mapping files and native symbols upload automatically on release builds. Dart symbols from `--obfuscate --split-debug-info` are uploaded with `firebase crashlytics:symbols:upload`. No player names, card names or room codes are attached to reports.

## Decisions worth knowing

- **Sequential passing:** passing goes one player at a time, as the brief describes, so the starter briefly holds 3 slips.
- **Win check:** both the passer's and the receiver's hands are checked after every pass. If both complete at once, the passer wins.
- **Leaving mid-round voids the round,** because the leaver's slips can't keep circulating. Disconnecting does not count as leaving.
- **No external movie API.** No legitimate one was configured, so the catalogue in `functions/src/engine/catalogue.ts` is the source of truth. The `familiar` flag is an editorial "well-known" marker, not a popularity ranking.
