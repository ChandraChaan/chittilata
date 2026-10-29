import { describe, expect, it } from "vitest";
import {
  GameError,
  KQ_DEFAULT_ROLES,
  kqCandidates,
  kqChain,
  kqGuess,
  kqMergeRoles,
  kqScores,
  KqState,
  kqStart,
  kqTimeoutTarget,
  seededRng,
  shuffle,
} from "../../src/engine";

const names = (n: number) => kqChain(KQ_DEFAULT_ROLES, n).map((r) => r.name);

/** A=King, B=Thief, C=Queen, D=Police (the worked example in the spec). */
function example(): KqState {
  return kqStart(["A", "B", "C", "D"], names(4), { A: 0, B: 3, C: 1, D: 2 });
}

const roleOf = (s: KqState, p: string) => s.chain[s.roles[p]];

/** Every invariant from spec §2.3. */
function checkInvariants(s: KqState) {
  expect(Object.values(s.roles).sort((a, b) => a - b)).toEqual(s.chain.map((_, i) => i));
  if (!s.done) {
    expect(s.roles[s.guesser]).toBe(s.step);
    expect(s.locked.map((p) => s.roles[p]).sort((a, b) => a - b)).toEqual([...Array(s.step).keys()]);
    for (const e of s.excluded) expect(s.roles[e]).not.toBe(s.step + 1);
    const holder = s.players.find((p) => s.roles[p] === s.step + 1)!;
    expect(kqCandidates(s)).toContain(holder);
  }
}

describe("role chain", () => {
  it("uses King, Queen, Police, Thief for four players", () => {
    expect(names(4)).toEqual(["King", "Queen", "Police", "Thief"]);
  });

  it("adds optional roles in a fixed order, keeping chain order", () => {
    expect(names(5)).toEqual(["King", "Queen", "Minister", "Police", "Thief"]);
    expect(names(6)).toEqual(["King", "Queen", "Minister", "Commander", "Police", "Thief"]);
    expect(names(7)).toEqual(["King", "Queen", "Minister", "Commander", "Police", "Merchant", "Thief"]);
    expect(names(10)).toEqual(KQ_DEFAULT_ROLES.map((r) => r.name));
    for (let n = 4; n <= 10; n++) {
      expect(names(n)).toHaveLength(n);
      expect(names(n)[0]).toBe("King");
      expect(names(n)[n - 1]).toBe("Thief");
    }
  });

  it("rejects fewer than 4 or more than 10 players", () => {
    expect(() => kqChain(KQ_DEFAULT_ROLES, 3)).toThrow(GameError);
    expect(() => kqChain(KQ_DEFAULT_ROLES, 11)).toThrow(GameError);
  });
});

describe("guessing transitions", () => {
  it("starts with the King guessing for the Queen", () => {
    const s = example();
    expect(s.guesser).toBe("A");
    expect(s.step).toBe(0);
    expect(kqCandidates(s).sort()).toEqual(["B", "C", "D"]);
  });

  it("a correct guess keeps the guesser's role and passes the turn to the found player", () => {
    const s = kqGuess(example(), "A", "C", 0);
    expect(s.locked).toEqual(["A"]);
    expect(s.guesser).toBe("C");
    expect(s.step).toBe(1);
    expect(roleOf(s, "A")).toBe("King");
    expect(roleOf(s, "C")).toBe("Queen");
    expect(s.excluded).toEqual([]);
  });

  it("a wrong guess exchanges roles and the guesser loses the turn", () => {
    const s = kqGuess(example(), "A", "B", 0);
    expect(roleOf(s, "B")).toBe("King");
    expect(roleOf(s, "A")).toBe("Thief");
    expect(s.guesser).toBe("B"); // the new King guesses next
    expect(s.step).toBe(0); // still looking for the Queen
    expect(s.excluded).toEqual(["A"]);
    expect(s.history[0]).toMatchObject({ guesser: "A", target: "B", correct: false });
  });

  it("follows the worked example in the specification exactly", () => {
    let s = example();
    s = kqGuess(s, "A", "B", 0); // wrong
    s = kqGuess(s, "B", "D", 1); // wrong, then the Queen is forced
    expect(s.history.map((h) => h.kind)).toEqual(["guess", "guess", "forced"]);
    expect(s.guesser).toBe("C");
    expect(s.locked).toEqual(["D"]);
    s = kqGuess(s, "C", "B", s.turnId); // correct, then the Thief is forced
    expect(s.done).toBe(true);
    expect({ D: roleOf(s, "D"), C: roleOf(s, "C"), B: roleOf(s, "B"), A: roleOf(s, "A") }).toEqual({
      D: "King",
      C: "Queen",
      B: "Police",
      A: "Thief",
    });
    expect(kqScores(s, KQ_DEFAULT_ROLES)).toEqual({ A: 100, B: 500, C: 800, D: 1000 });
  });

  it("the last step is always forced", () => {
    let s = kqGuess(example(), "A", "C", 0); // Queen found
    s = kqGuess(s, "C", "D", s.turnId); // Police found, Thief forced
    expect(s.done).toBe(true);
    expect(s.history.at(-1)!.kind).toBe("forced");
    expect(s.locked.sort()).toEqual(["A", "B", "C", "D"]);
  });

  it("rejects guesses out of turn, stale turns, self, locked or excluded players", () => {
    const s0 = example();
    expect(() => kqGuess(s0, "B", "C", 0)).toThrow(/not your turn/);
    expect(() => kqGuess(s0, "A", "A", 0)).toThrow(/can't pick/);
    expect(() => kqGuess(s0, "A", "Z", 0)).toThrow(/can't pick/);
    const s1 = kqGuess(s0, "A", "B", 0); // A excluded now
    expect(() => kqGuess(s1, "B", "A", 1)).toThrow(/can't pick/);
    expect(() => kqGuess(s1, "B", "C", 0)).toThrow(/already finished/);
    const s2 = kqGuess(example(), "A", "C", 0); // A locked
    expect(() => kqGuess(s2, "C", "A", s2.turnId)).toThrow(/can't pick/);
  });

  it("a finished round accepts no more guesses", () => {
    let s = kqGuess(example(), "A", "C", 0);
    s = kqGuess(s, "C", "D", s.turnId);
    expect(() => kqGuess(s, s.guesser, "A", s.turnId)).toThrow(/round is over/);
    expect(kqCandidates(s)).toEqual([]);
  });

  it("timeouts guess a random candidate on the guesser's behalf", () => {
    const s = example();
    const t = kqTimeoutTarget(s, seededRng(3));
    expect(kqCandidates(s)).toContain(t);
    const next = kqGuess(s, "server", t, 0, "timeout");
    expect(next.history[0].kind).toBe("timeout");
    expect(next.history[0].guesser).toBe("A");
  });
});

describe("properties over random play (termination, consistency, fairness)", () => {
  for (let n = 4; n <= 10; n++) {
    it(`${n} players: always terminates within N(N-1)/2 guesses with valid states`, () => {
      const chain = names(n);
      const players = Array.from({ length: n }, (_, i) => `p${i}`);
      for (let seed = 0; seed < 150; seed++) {
        const rng = seededRng(seed * 31 + n);
        const perm = shuffle([...Array(n).keys()], rng);
        const roles = Object.fromEntries(players.map((p, i) => [p, perm[i]]));
        let s = kqStart(players, chain, roles);
        checkInvariants(s);
        let guesses = 0;
        while (!s.done) {
          const c = kqCandidates(s);
          s = kqGuess(s, s.guesser, c[rng(c.length)], s.turnId);
          checkInvariants(s);
          guesses++;
          expect(guesses).toBeLessThanOrEqual((n * (n - 1)) / 2);
        }
        expect(s.history.length).toBeLessThanOrEqual((n * (n - 1)) / 2);
        expect(s.locked.slice().sort()).toEqual(players.slice().sort());
        // Points are a permutation of the role points.
        const pts = Object.values(kqScores(s, KQ_DEFAULT_ROLES)).sort((a, b) => a - b);
        expect(pts).toEqual(kqChain(KQ_DEFAULT_ROLES, n).map((r) => r.points).sort((a, b) => a - b));
      }
    });
  }

  it("never lets the same player be guessed twice in one step", () => {
    const rng = seededRng(5);
    for (let k = 0; k < 200; k++) {
      const players = ["a", "b", "c", "d", "e", "f"];
      const perm = shuffle([0, 1, 2, 3, 4, 5], rng);
      let s = kqStart(players, names(6), Object.fromEntries(players.map((p, i) => [p, perm[i]])));
      while (!s.done) {
        const c = kqCandidates(s);
        s = kqGuess(s, s.guesser, c[rng(c.length)], s.turnId);
      }
      const seen = new Set<string>();
      for (const h of s.history) {
        const key = `${h.step}:${h.target}`;
        // A wrong target becomes the guesser, so it can't be a target again in that step.
        expect(seen.has(key)).toBe(false);
        seen.add(key);
      }
    }
  });
});

describe("settings", () => {
  it("lets the host change points and optional role names only", () => {
    const next = kqMergeRoles(KQ_DEFAULT_ROLES, [
      { key: "king", name: "Raja", points: 1200 },
      { key: "minister", name: "Mantri", points: 650 },
    ]);
    expect(next.find((r) => r.key === "king")).toMatchObject({ name: "King", points: 1200 });
    expect(next.find((r) => r.key === "minister")).toMatchObject({ name: "Mantri", points: 650 });
  });

  it("rejects invalid points and duplicate names", () => {
    expect(() => kqMergeRoles(KQ_DEFAULT_ROLES, [{ key: "queen", points: -1 }])).toThrow(GameError);
    expect(() => kqMergeRoles(KQ_DEFAULT_ROLES, [{ key: "queen", points: 1.5 }])).toThrow(GameError);
    expect(() => kqMergeRoles(KQ_DEFAULT_ROLES, [{ key: "poet", name: "Thief", points: 300 }])).toThrow(/different/);
    expect(() => kqMergeRoles(KQ_DEFAULT_ROLES, [{ key: "poet", name: "", points: 300 }])).toThrow(GameError);
  });
});
