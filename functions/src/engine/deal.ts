import { randomId, shuffle } from "./random";
import {
  Card,
  COPIES_PER_NAME,
  GameError,
  HAND_SIZE,
  MAX_PLAYERS,
  MIN_PLAYERS,
  Rng,
} from "./types";

/**
 * Opening-hand constraints.
 *
 * With N players there are N names and 4 copies of each (4N cards).
 * - N >= 4: every hand holds 4 different names (max 1 copy per name).
 * - N == 3: only 3 names exist, so 4 different names is impossible. The most
 *   diverse legal hand is 2+1+1: three different names, at most 2 copies.
 * In every case no player can start with 3 or 4 copies of a name, so nobody
 * can win before the first pass.
 */
export function dealConstraints(playerCount: number): {
  maxCopies: number;
  minDistinct: number;
} {
  if (playerCount < MIN_PLAYERS || playerCount > MAX_PLAYERS) {
    throw new GameError(
      "invalid-argument",
      `Chittilata needs ${MIN_PLAYERS}-${MAX_PLAYERS} players.`,
    );
  }
  return playerCount >= HAND_SIZE
    ? { maxCopies: 1, minDistinct: HAND_SIZE }
    : { maxCopies: 2, minDistinct: playerCount };
}

/** Builds the deck: 4 copies of each name, each with a unique random id. */
export function buildDeck(names: string[], rng: Rng): Card[] {
  const ids = new Set<string>();
  const deck: Card[] = [];
  for (const name of names) {
    for (let c = 0; c < COPIES_PER_NAME; c++) {
      let id = randomId(rng);
      while (ids.has(id)) id = randomId(rng);
      ids.add(id);
      deck.push({ id, name });
    }
  }
  return deck;
}

/**
 * Deals 4 cards to each player satisfying dealConstraints, uniformly
 * randomising both card order and seat order before a backtracking search.
 * Seat index carries no advantage: the caller maps hands onto a shuffled
 * player order.
 */
export function dealHands(deck: Card[], playerCount: number, rng: Rng): Card[][] {
  const { maxCopies, minDistinct } = dealConstraints(playerCount);
  if (deck.length !== playerCount * HAND_SIZE) {
    throw new GameError(
      "invalid-argument",
      `Deck has ${deck.length} cards; ${playerCount * HAND_SIZE} needed.`,
    );
  }

  for (let attempt = 0; attempt < 50; attempt++) {
    const cards = shuffle(deck, rng);
    const hands: Card[][] = Array.from({ length: playerCount }, () => []);
    const counts: Map<string, number>[] = hands.map(() => new Map());
    let steps = 0;

    const canTake = (p: number, card: Card): boolean => {
      const hand = hands[p];
      if (hand.length >= HAND_SIZE) return false;
      const have = counts[p].get(card.name) ?? 0;
      if (have + 1 > maxCopies) return false;
      const distinctAfter = counts[p].size + (have === 0 ? 1 : 0);
      const slotsLeft = HAND_SIZE - (hand.length + 1);
      return distinctAfter + slotsLeft >= minDistinct;
    };

    const place = (i: number): boolean => {
      if (i === cards.length) return true;
      if (++steps > 20000) return false;
      const card = cards[i];
      for (const p of shuffle([...Array(playerCount).keys()], rng)) {
        if (!canTake(p, card)) continue;
        hands[p].push(card);
        counts[p].set(card.name, (counts[p].get(card.name) ?? 0) + 1);
        if (place(i + 1)) return true;
        hands[p].pop();
        const left = (counts[p].get(card.name) ?? 1) - 1;
        if (left === 0) counts[p].delete(card.name);
        else counts[p].set(card.name, left);
      }
      return false;
    };

    if (place(0)) {
      validateDeal(hands, deck);
      return hands;
    }
  }
  throw new GameError(
    "failed-precondition",
    "Could not produce a valid opening deal for this configuration.",
  );
}

/** Throws if a deal breaks any rule. Run before every round starts. */
export function validateDeal(hands: Card[][], deck: Card[]): void {
  const { maxCopies, minDistinct } = dealConstraints(hands.length);
  const fail = (why: string) => {
    throw new GameError("failed-precondition", `Invalid deal: ${why}`);
  };

  const deckIds = new Set(deck.map((c) => c.id));
  if (deckIds.size !== deck.length) fail("duplicate card ids in deck");
  const seen = new Set<string>();
  const totals = new Map<string, number>();

  hands.forEach((hand, p) => {
    if (hand.length !== HAND_SIZE) fail(`seat ${p} has ${hand.length} cards`);
    const counts = new Map<string, number>();
    for (const card of hand) {
      if (!deckIds.has(card.id)) fail(`unknown card ${card.id}`);
      if (seen.has(card.id)) fail(`card ${card.id} dealt twice`);
      seen.add(card.id);
      counts.set(card.name, (counts.get(card.name) ?? 0) + 1);
      totals.set(card.name, (totals.get(card.name) ?? 0) + 1);
    }
    if (Math.max(...counts.values()) > maxCopies) {
      fail(`seat ${p} has too many copies of one name`);
    }
    if (counts.size < minDistinct) fail(`seat ${p} hand is not diverse enough`);
  });

  if (seen.size !== deck.length) fail("not every card was dealt");
  for (const [name, n] of totals) {
    if (n !== COPIES_PER_NAME) fail(`${name} dealt ${n} times`);
  }
}
