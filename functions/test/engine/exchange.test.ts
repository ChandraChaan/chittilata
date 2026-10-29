import { describe, expect, it } from "vitest";
import {
  applyPass,
  assignCharacters,
  Card,
  charactersFor,
  currentPlayer,
  DEFAULT_CHARACTERS,
  defaultSettings,
  GameError,
  initialExchange,
  mergeSettings,
  nextPlayer,
  rankPlayers,
  titleTie,
  roundScores,
  seededRng,
  shuffle,
  timeoutCard,
  validateForStart,
} from "../../src/engine";

const card = (id: string, name: string): Card => ({ id, name });

/** Chandra holds A A A B and wants the fourth A, as in the spec. */
function specExample() {
  const hands: Record<string, Card[]> = {
    chandra: [card("a1", "A"), card("a2", "A"), card("a3", "A"), card("b1", "B")],
    vasavi: [card("a4", "A"), card("b2", "B"), card("c1", "C"), card("d1", "D")],
    swetha: [card("b3", "B"), card("c2", "C"), card("d2", "D"), card("c3", "C")],
    sai: [card("b4", "B"), card("c4", "C"), card("d3", "D"), card("d4", "D")],
  };
  return initialExchange(["chandra", "vasavi", "swetha", "sai"], hands);
}

const total = (s: ReturnType<typeof specExample>) =>
  Object.values(s.hands).reduce((n, h) => n + h.length, 0);

describe("applyPass", () => {
  it("moves one card to the next player and advances the turn", () => {
    const s0 = specExample();
    const r = applyPass(s0, "chandra", "b1", 0);
    expect(r.toUid).toBe("vasavi");
    expect(r.state.hands.chandra).toHaveLength(3);
    expect(r.state.hands.vasavi).toHaveLength(5);
    expect(r.state.incoming.vasavi).toBe("b1");
    expect(currentPlayer(r.state)).toBe("vasavi");
    expect(nextPlayer(r.state)).toBe("swetha");
    expect(r.state.turnId).toBe(1);
    expect(total(r.state)).toBe(16);
    // input untouched
    expect(s0.hands.chandra).toHaveLength(4);
  });

  it("lets the receiver inspect the incoming card and pass any of their five", () => {
    const s1 = applyPass(specExample(), "chandra", "b1", 0).state;
    expect(s1.hands.vasavi.map((c) => c.id)).toContain("b1");
    const r = applyPass(s1, "vasavi", "a4", 1);
    expect(r.state.hands.vasavi).toHaveLength(4);
    expect(r.state.hands.swetha).toHaveLength(5);
  });

  it("detects the spec's winning scenario when the fourth A comes round", () => {
    let s = applyPass(specExample(), "chandra", "b1", 0).state; // chandra: A A A
    s = applyPass(s, "vasavi", "a4", 1).state; // swetha gets A
    s = applyPass(s, "swetha", "a4", 2).state; // sai gets A
    const r = applyPass(s, "sai", "a4", 3); // chandra gets A -> 4 matching
    expect(r.winner).toEqual({ uid: "chandra", name: "A" });
    expect(total(r.state)).toBe(16);
  });

  it("detects a win on the passer's hand after passing the odd card", () => {
    const hands: Record<string, Card[]> = {
      p1: [card("x1", "X"), card("y1", "Y"), card("z1", "Z")],
      p2: [card("x2", "X"), card("x3", "X"), card("x4", "X"), card("y2", "Y"), card("x5", "X")],
      p3: [card("y3", "Y"), card("z2", "Z"), card("z3", "Z"), card("y4", "Y")],
    };
    const s = { ...initialExchange(["p1", "p2", "p3"], hands), turnIndex: 1, turnId: 5 };
    const r = applyPass(s, "p2", "y2", 5);
    expect(r.winner).toEqual({ uid: "p2", name: "X" });
  });

  it("rejects a player acting out of turn", () => {
    expect(() => applyPass(specExample(), "vasavi", "a4", 0)).toThrow(/not your turn/);
  });

  it("rejects a card the player does not hold", () => {
    expect(() => applyPass(specExample(), "chandra", "a4", 0)).toThrow(/card you hold/);
  });

  it("rejects a stale or duplicate turn id so a retry cannot double-pass", () => {
    const r = applyPass(specExample(), "chandra", "b1", 0);
    expect(() => applyPass(r.state, "chandra", "a1", 0)).toThrow(GameError);
    expect(() => applyPass(r.state, "vasavi", "b1", 0)).toThrow(/already finished/);
  });

  it("cannot pass the same card twice", () => {
    const r = applyPass(specExample(), "chandra", "b1", 0);
    // b1 now belongs to vasavi; chandra can no longer pass it even on her next turn
    let s = r.state;
    s = applyPass(s, "vasavi", "c1", 1).state;
    s = applyPass(s, "swetha", "c1", 2).state;
    s = applyPass(s, "sai", "c1", 3).state;
    expect(() => applyPass(s, "chandra", "b1", 4)).toThrow(/card you hold/);
  });

  it("preserves card count and hand sizes over a long random game", () => {
    const rng = seededRng(77);
    let s = specExample();
    for (let i = 0; i < 400; i++) {
      const uid = currentPlayer(s);
      const hand = s.hands[uid];
      const r = applyPass(s, uid, hand[rng(hand.length)].id, s.turnId);
      s = r.state;
      expect(total(s)).toBe(16);
      const sizes = Object.values(s.hands).map((h) => h.length).sort();
      expect(sizes.every((n) => n >= 3 && n <= 5)).toBe(true);
      if (r.winner) break;
    }
  });
});

describe("timeoutCard", () => {
  const hand = [card("a", "A"), card("b", "B"), card("c", "C"), card("d", "D"), card("e", "E")];
  it("passIncoming passes the card just received", () => {
    expect(timeoutCard(hand, "c", "passIncoming", seededRng(1)).id).toBe("c");
  });
  it("passIncoming falls back to random with no incoming card", () => {
    expect(hand.map((c) => c.id)).toContain(timeoutCard(hand, null, "passIncoming", seededRng(1)).id);
  });
  it("passRandom picks from the hand", () => {
    expect(hand.map((c) => c.id)).toContain(timeoutCard(hand, "c", "passRandom", seededRng(2)).id);
  });
});

describe("characters", () => {
  it("uses Queen, Thief, Police for a four-player game", () => {
    expect(charactersFor(DEFAULT_CHARACTERS, 3).map((c) => c.name).sort()).toEqual([
      "Police",
      "Queen",
      "Thief",
    ]);
  });

  it("gives each non-winner exactly one distinct character", () => {
    for (let n = 2; n <= 9; n++) {
      const uids = Array.from({ length: n }, (_, i) => `u${i}`);
      const a = assignCharacters(uids, DEFAULT_CHARACTERS, seededRng(n));
      expect(Object.keys(a).sort()).toEqual(uids.slice().sort());
      expect(new Set(Object.values(a).map((c) => c.name)).size).toBe(n);
    }
  });

  it("refuses when too few characters are configured", () => {
    expect(() => charactersFor(DEFAULT_CHARACTERS.slice(0, 2), 3)).toThrow(/needs 3/);
  });
});

describe("scoring", () => {
  it("awards win points to the winner and character points to the rest", () => {
    const s = roundScores(["a", "b", "c", "d"], "a", 1000, {
      b: { points: 800 },
      c: { points: 500 },
      d: { points: 100 },
    });
    expect(s).toEqual({ a: 1000, b: 800, c: 500, d: 100 });
  });

  it("ranks by total then movie wins, crowning King and Queen", () => {
    const r = rankPlayers([
      { uid: "a", name: "Sai", total: 5000, movieWins: 1 },
      { uid: "b", name: "Chandra", total: 6000, movieWins: 2 },
      { uid: "c", name: "Vasavi", total: 5000, movieWins: 3 },
      { uid: "d", name: "Swetha", total: 1000, movieWins: 0 },
    ]);
    expect(r.map((p) => [p.uid, p.rank, p.title])).toEqual([
      ["b", 1, "King"],
      ["c", 2, "Queen"],
      ["a", 3, null],
      ["d", 4, null],
    ]);
  });

  it("shares rank and title on a full tie instead of inventing a winner", () => {
    const r = rankPlayers([
      { uid: "a", name: "Zed", total: 3000, movieWins: 1 },
      { uid: "b", name: "Amy", total: 3000, movieWins: 1 },
      { uid: "c", name: "Bo", total: 2000, movieWins: 1 },
    ]);
    expect(r.map((p) => [p.uid, p.rank, p.title])).toEqual([
      ["b", 1, "King"],
      ["a", 1, "King"],
      ["c", 3, "Queen"],
    ]);
  });

  it("a tie-breaker result orders tied players without touching totals", () => {
    const r = rankPlayers([
      { uid: "a", name: "Amy", total: 3000, movieWins: 1, tiebreak: 100 },
      { uid: "b", name: "Bo", total: 3000, movieWins: 1, tiebreak: 1000 },
      { uid: "c", name: "Cy", total: 2000, movieWins: 0 },
    ]);
    expect(r.map((p) => [p.uid, p.rank, p.title, p.total])).toEqual([
      ["b", 1, "King", 3000],
      ["a", 2, "Queen", 3000],
      ["c", 3, null, 2000],
    ]);
  });

  it("finds the tie that decides a title", () => {
    const kings = rankPlayers([
      { uid: "a", name: "A", total: 3000, movieWins: 1 },
      { uid: "b", name: "B", total: 3000, movieWins: 1 },
      { uid: "c", name: "C", total: 100, movieWins: 0 },
    ]);
    expect(titleTie(kings)).toEqual({ title: "King", uids: ["a", "b"] });
    const queens = rankPlayers([
      { uid: "a", name: "A", total: 5000, movieWins: 2 },
      { uid: "b", name: "B", total: 3000, movieWins: 1 },
      { uid: "c", name: "C", total: 3000, movieWins: 1 },
      { uid: "d", name: "D", total: 100, movieWins: 0 },
    ]);
    expect(titleTie(queens)).toEqual({ title: "Queen", uids: ["b", "c"] });
    const none = rankPlayers([
      { uid: "a", name: "A", total: 5000, movieWins: 2 },
      { uid: "b", name: "B", total: 3000, movieWins: 1 },
      { uid: "c", name: "C", total: 100, movieWins: 0 },
      { uid: "d", name: "D", total: 100, movieWins: 0 },
    ]);
    expect(titleTie(none)).toBeNull();
    const withLeaver = rankPlayers([
      { uid: "a", name: "A", total: 3000, movieWins: 1, left: true },
      { uid: "b", name: "B", total: 3000, movieWins: 1 },
      { uid: "c", name: "C", total: 100, movieWins: 0 },
    ]);
    expect(titleTie(withLeaver)).toBeNull();
  });

  it("accumulates round scores correctly", () => {
    const rounds = [
      { a: 1000, b: 800, c: 100 },
      { a: 100, b: 1000, c: 800 },
      { a: 800, b: 100, c: 1000 },
    ];
    const totals: Record<string, number> = {};
    for (const r of rounds) for (const [u, p] of Object.entries(r)) totals[u] = (totals[u] ?? 0) + p;
    expect(totals).toEqual({ a: 1900, b: 1900, c: 1900 });
  });
});

describe("settings", () => {
  it("validates and merges patches", () => {
    const s = mergeSettings(defaultSettings(), { rounds: 10, turnSeconds: 15, category: "hollywood" });
    expect(s.rounds).toBe(10);
    expect(s.turnSeconds).toBe(15);
    expect(s.category).toBe("hollywood");
  });

  it("rejects bad values", () => {
    const d = defaultSettings();
    expect(() => mergeSettings(d, { rounds: 0 })).toThrow(GameError);
    expect(() => mergeSettings(d, { turnSeconds: 7 })).toThrow(GameError);
    expect(() => mergeSettings(d, { category: "anime" })).toThrow(GameError);
    expect(() => mergeSettings(d, { winPoints: 1e9 })).toThrow(GameError);
    expect(() => mergeSettings(d, { characters: [{ name: "Q", points: 1 }] })).toThrow(GameError);
    expect(() =>
      mergeSettings(d, { characters: [{ name: "Q", points: 1 }, { name: "q", points: 2 }] }),
    ).toThrow(/different/);
  });

  it("blocks starting with too few custom names or characters", () => {
    const custom = mergeSettings(defaultSettings(), { category: "custom", customNames: ["A", "B", "C"] });
    expect(() => validateForStart(custom, 4)).toThrow(/at least 4/);
    const fewChars = mergeSettings(defaultSettings(), {
      characters: [{ name: "Queen", points: 800 }, { name: "Thief", points: 100 }],
    });
    expect(() => validateForStart(fewChars, 4)).toThrow(/needs 3/);
    expect(() => validateForStart(defaultSettings(), 2)).toThrow(/3-10/);
    expect(() => validateForStart(defaultSettings(), 10)).not.toThrow();
  });

  it("random circular order contains every player exactly once", () => {
    const players = ["Chandra", "Vasavi", "Swetha", "Sai", "Ravi"];
    for (let seed = 0; seed < 50; seed++) {
      const order = shuffle(players, seededRng(seed));
      expect(order.slice().sort()).toEqual(players.slice().sort());
    }
  });
});
