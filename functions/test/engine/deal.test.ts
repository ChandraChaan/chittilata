import { describe, expect, it } from "vitest";
import {
  buildDeck,
  dealConstraints,
  dealHands,
  eligibleNames,
  GameError,
  pickNames,
  seededRng,
  shuffle,
  validateDeal,
  winningName,
} from "../../src/engine";

const names = (n: number) => Array.from({ length: n }, (_, i) => `Movie ${i + 1}`);

describe("buildDeck", () => {
  it("creates 4 copies of every name with unique ids", () => {
    const deck = buildDeck(names(4), seededRng(1));
    expect(deck).toHaveLength(16);
    expect(new Set(deck.map((c) => c.id)).size).toBe(16);
    for (const n of names(4)) {
      expect(deck.filter((c) => c.name === n)).toHaveLength(4);
    }
  });
});

describe("dealHands", () => {
  for (let players = 3; players <= 10; players++) {
    it(`deals valid diverse hands for ${players} players across many seeds`, () => {
      const { maxCopies, minDistinct } = dealConstraints(players);
      for (let seed = 0; seed < 200; seed++) {
        const rng = seededRng(seed * 7919 + players);
        const deck = buildDeck(names(players), rng);
        const hands = dealHands(deck, players, rng);
        expect(hands).toHaveLength(players);
        for (const hand of hands) {
          expect(hand).toHaveLength(4);
          const counts = new Map<string, number>();
          hand.forEach((c) => counts.set(c.name, (counts.get(c.name) ?? 0) + 1));
          expect(Math.max(...counts.values())).toBeLessThanOrEqual(maxCopies);
          expect(counts.size).toBeGreaterThanOrEqual(minDistinct);
          expect(winningName(hand)).toBeNull();
        }
        const all = hands.flat();
        expect(new Set(all.map((c) => c.id)).size).toBe(deck.length);
      }
    });
  }

  it("gives 4 players 4 different movies each", () => {
    const rng = seededRng(42);
    const hands = dealHands(buildDeck(["Pushpa 2", "Devara", "Salaar", "RRR"], rng), 4, rng);
    for (const hand of hands) expect(new Set(hand.map((c) => c.name)).size).toBe(4);
  });

  it("never gives 3 players a triple; every hand is 2+1+1", () => {
    for (let seed = 0; seed < 300; seed++) {
      const rng = seededRng(seed);
      const hands = dealHands(buildDeck(names(3), rng), 3, rng);
      for (const hand of hands) {
        const counts = new Map<string, number>();
        hand.forEach((c) => counts.set(c.name, (counts.get(c.name) ?? 0) + 1));
        expect([...counts.values()].sort()).toEqual([1, 1, 2]);
      }
    }
  });

  it("does not favour any seat: each seat sees each name about equally", () => {
    // With 3 players each seat holds a double of some name; check the
    // doubled name is spread evenly across seats over many deals.
    const doubles = [new Map<string, number>(), new Map(), new Map()];
    const rng = seededRng(99);
    for (let i = 0; i < 3000; i++) {
      const hands = dealHands(buildDeck(names(3), rng), 3, rng);
      hands.forEach((hand, seat) => {
        const counts = new Map<string, number>();
        hand.forEach((c) => counts.set(c.name, (counts.get(c.name) ?? 0) + 1));
        for (const [n, k] of counts) if (k === 2) doubles[seat].set(n, (doubles[seat].get(n) ?? 0) + 1);
      });
    }
    for (const seat of doubles) {
      for (const n of names(3)) {
        const share = (seat.get(n) ?? 0) / 3000;
        expect(share).toBeGreaterThan(0.28);
        expect(share).toBeLessThan(0.39);
      }
    }
  });

  it("rejects unsupported player counts explicitly", () => {
    expect(() => dealConstraints(2)).toThrow(GameError);
    expect(() => dealConstraints(11)).toThrow(GameError);
    const rng = seededRng(1);
    expect(() => dealHands(buildDeck(names(4), rng), 5, rng)).toThrow(/Deck has 16/);
  });
});

describe("validateDeal", () => {
  it("rejects a hand with a triple", () => {
    const rng = seededRng(3);
    const deck = buildDeck(names(4), rng);
    const byName = (n: string) => deck.filter((c) => c.name === n);
    const [a, b, c, d] = names(4).map(byName);
    const hands = [
      [a[0], a[1], a[2], b[0]],
      [a[3], b[1], c[0], d[0]],
      [b[2], c[1], d[1], c[2]],
      [b[3], c[3], d[2], d[3]],
    ];
    expect(() => validateDeal(hands, deck)).toThrow(/too many copies/);
  });

  it("rejects a duplicated card", () => {
    const rng = seededRng(4);
    const deck = buildDeck(names(4), rng);
    const hands = dealHands(deck, 4, rng);
    hands[1][0] = hands[0][0];
    expect(() => validateDeal(hands, deck)).toThrow(/Invalid deal/);
  });
});

describe("catalogue", () => {
  it("easy is a subset of normal, which is a subset of challenging", () => {
    const easy = eligibleNames("telugu", "easy", []);
    const normal = eligibleNames("telugu", "normal", []);
    const hard = eligibleNames("telugu", "challenging", []);
    expect(easy.length).toBeGreaterThanOrEqual(10);
    expect(normal.length).toBeGreaterThan(easy.length);
    expect(hard.length).toBeGreaterThan(normal.length);
    for (const n of easy) expect(normal).toContain(n);
    for (const n of normal) expect(hard).toContain(n);
  });

  it("every category has enough names for 10 players on easy", () => {
    for (const c of ["telugu", "indian", "hollywood", "mixed"] as const) {
      expect(eligibleNames(c, "easy", []).length).toBeGreaterThanOrEqual(10);
    }
  });

  it("dedupes custom names case-insensitively", () => {
    expect(eligibleNames("custom", "hard" as never, ["India", " india ", "Japan", ""])).toEqual([
      "India",
      "Japan",
    ]);
  });

  it("prefers unused names and only reuses when the pool runs out", () => {
    const pool = names(6);
    const rng = seededRng(5);
    const first = pickNames(pool, 4, [], rng);
    const second = pickNames(pool, 4, first, rng);
    const fresh = second.filter((n) => !first.includes(n));
    expect(fresh).toHaveLength(2);
    expect(new Set(second).size).toBe(4);
  });

  it("refuses when there are too few names", () => {
    expect(() => pickNames(names(3), 4, [], seededRng(1))).toThrow(/at least 4/);
  });

  it("shuffle keeps every element", () => {
    const s = shuffle(names(10), seededRng(8));
    expect(s.slice().sort()).toEqual(names(10).sort());
  });
});
