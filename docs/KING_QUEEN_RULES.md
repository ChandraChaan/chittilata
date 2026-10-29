# King & Queen — Rules specification and state model

King & Queen is Chittilata's second game mode, a secret-role guessing game played with folded paper chits. This document is the **source of truth** for the rules. The engine (`functions/src/engine/kingqueen.ts`) and its tests (`functions/test/engine/kingqueen.test.ts`) implement exactly what is written here.

## 1. Players and roles

- **4–10 players**, each on their own phone.
- Roles form a **chain**: each role-holder must find the holder of the **next** role in the chain.

**Role catalogue** (chain order, default points). The host can change every role's points; the four core role names are fixed, and the optional roles can be renamed.

| Chain position | Role | Default points | Used when players ≥ |
|---:|---|---:|---:|
| 1 | King | 1000 | 4 (always) |
| 2 | Queen | 800 | 4 (always) |
| 3 | Minister | 700 | 5 |
| 4 | Commander | 600 | 6 |
| 5 | Police | 500 | 4 (always) |
| 6 | Merchant | 400 | 7 |
| 7 | Poet | 300 | 8 |
| 8 | Farmer | 200 | 9 |
| 9 | Jester | 150 | 10 |
| 10 | Thief | 100 | 4 (always) |

With **N players** the game uses King, Queen, Police and Thief, plus the first N − 4 optional roles in this order: Minister, Commander, Merchant, Poet, Farmer, Jester. The chosen roles keep their **catalogue order**, and that order is the chain. So every player count has exactly one unambiguous chain:

| Players | Chain |
|---:|---|
| 4 | King → Queen → Police → Thief |
| 5 | King → Queen → Minister → Police → Thief |
| 6 | King → Queen → Minister → Commander → Police → Thief |
| 7 | … → Police → Merchant → Thief |
| 8 | … → Merchant → Poet → Thief |
| 9 | … → Poet → Farmer → Thief |
| 10 | … → Farmer → Jester → Thief |

## 2. Round flow

```
picking ──(all chits picked)──▶ guessing ──(every role locked)──▶ revealed
   │                               │
   └──(a player leaves)──▶ aborted ◀┘
```

### 2.1 Picking (paper chits)
1. The server seals one role into each of N folded chits, shuffled with a cryptographically secure RNG. The public round shows only opaque chit ids.
2. Every phone shows the ceremony: role names are written on paper, folded, collapsed into one pile, shuffled and scattered on the mat.
3. Each player picks **exactly one** chit. A chit can be taken once; a player can take one. **The role inside is the player's role.** Only that player sees it.
4. After 20 seconds, any member may ask the server to hand out the remaining chits at random.
5. When every chit is picked, guessing begins. The **King is announced publicly**, because the King must call the first guess.

### 2.2 Guessing

State (server-authoritative):

| Field | Meaning | Visibility |
|---|---|---|
| `step` *s* | the guesser holds chain[s] and must find chain[s+1] | public |
| `guesser` *g* | player who must guess now | public |
| `locked` *L* | players whose role is final, with that role | public |
| `excluded` *E* | players known **not** to hold chain[s+1] in this step | public |
| `turnId`, `deadline` | turn counter and server deadline | public |
| `roles` | uid → role | **private**; each player sees only their own until the reveal |
| `history` | every guess: who, whom, right/wrong, forced/timeout | public |

**Candidates** *C* = all players − *L* − {*g*} − *E*.

**Guess** (only *g*, only on the current `turnId`, only before the deadline, target *t* ∈ *C*):

- **Correct**, i.e. role(t) = chain[s+1]:
  - *g* keeps their role and it becomes final: *L* += *g*.
  - *t* is publicly revealed as chain[s+1] and becomes the guesser: *g* := *t*, *s* += 1, *E* := ∅.
- **Incorrect**, i.e. role(t) ≠ chain[s+1]:
  - *g* and *t* **exchange roles**. *t* now publicly holds chain[s]; *g* now privately holds *t*'s old role.
  - The guesser **loses the turn**: *t* becomes the guesser for the **same step** (they must now find chain[s+1]).
  - *E* += old *g*, because the old guesser now holds *t*'s old role, which is known not to be chain[s+1]. Everyone already in *E* keeps their role, so they stay excluded.
- Then **forced resolution**: while the round isn't over and |*C*| = 1, the single candidate must hold chain[s+1]. That holder isn't locked (locked players hold chain[0..s−1]), isn't the guesser, and isn't excluded (excluded players hold other roles). So the server applies that correct guess automatically and logs it as **forced**.
- **Round over**: when *s* = N − 1, the guesser holds the last role (Thief), which is final: *L* += *g*. Every role is now locked.

**Timeout.** If the guesser doesn't guess before the deadline (plus 1 second of grace), any member may ask the server to apply the timeout. The server then makes a **uniformly random** guess from *C* on the guesser's behalf, with the same transitions. A timeout never helps or hurts anyone in particular. The host sets the turn timer (10–60 s), or picks **No timer**, which still auto-guesses after 5 minutes so the game can't freeze.

### 2.3 Guarantees (each one is tested)

1. **Permutation:** roles are always a permutation of the chain. Exchanges never create or destroy a role.
2. **Consistency:** locked players hold exactly chain[0..s−1], the guesser holds chain[s], and excluded players never hold chain[s+1].
3. **Termination:** within a step every wrong guess shrinks *C* by one, so after at most |*C*| − 1 wrong guesses the forced rule fires. Every correct guess advances *s*. A round therefore ends after at most N(N−1)/2 guesses. No infinite loops.
4. **No duplicate or invalid actions:** a guess must come from the current guesser, carry the current `turnId`, target a current candidate, and arrive before the deadline. A replayed request (same `requestId`) returns the original result and changes nothing. Of two simultaneous requests for one turn, exactly one applies; the other fails on `turnId`.
5. **Privacy:** an unlocked player's role is only ever readable by that player, until the reveal.

## 3. Scoring

- At the end of a round, every player scores the points of their **final** role.
- Totals accumulate across rounds. Round scores are stored per round so they can be audited.
- **Final ranking:** highest total first. **Ties** go to the player who finished the most rounds as **King**. Players still tied **share** the rank and the title, for example "Joint Kings". The top rank is **King** and the next rank is **Queen**, exactly as in Movie Chits.
- A Movie-Chits-style extra tie-breaker round is **not** offered, because a King & Queen round needs at least 4 players. The King-finishes rule is the tie-breaker.

## 4. Rounds and settings (host only, in the lobby)

- Rounds: 1–30 (presets 5, 7, 10, 15).
- Turn timer: 10, 15, 20, 30, 45 or 60 s, or No timer.
- Role points for every role (0–5000); names for optional roles (1–16 characters, unique).

## 5. Leaving and reconnecting

- Disconnecting doesn't remove you: deadlines keep running, and a missed guess is made at random.
- **Leaving** during picking or guessing **voids the round** (no points), and it counts as played. If fewer than 4 players remain, the game ends with the totals so far.

## 6. Worked example (4 players)

Roles after picking: A = King, B = Thief, C = Queen, D = Police. A is publicly the King.

1. A guesses **B** for Queen: wrong. A and B swap, so B is publicly King and A privately holds Thief. *E* = {A}, guesser = B.
2. B guesses **D** for Queen: wrong. B and D swap, so D is publicly King and B privately holds Police. *E* = {A, B}, guesser = D.
3. Candidates for Queen are now {C}: **forced**. D is locked as King, and C is revealed as Queen and becomes the guesser.
4. C must find Police among {A, B}. C guesses **B**: correct. C is locked as Queen, B is revealed as Police and becomes the guesser.
5. The only candidate left is A: **forced**. B is locked as Police, A is revealed as Thief and locked.

Final: D King 1000, C Queen 800, B Police 500, A Thief 100.
