import { Card, GameError, HAND_SIZE, Rng, TimeoutPolicy } from "./types";

/**
 * The exchange is sequential around a fixed circle.
 *
 * Everyone is dealt 4 cards. The round starter (order[0]) passes first, so
 * they briefly hold 3 cards until the card travelling around the circle comes
 * back to them. Every other player receives a card (holding 5), inspects it,
 * and passes one of their 5 to the next seat, returning to 4.
 */
export interface ExchangeState {
  order: string[];
  /** Index into `order` of the player who must pass next. */
  turnIndex: number;
  /** Increments on every completed pass; used to reject stale requests. */
  turnId: number;
  hands: Record<string, Card[]>;
  /** The card id each player most recently received (null if none pending). */
  incoming: Record<string, string | null>;
}

export interface PassResult {
  state: ExchangeState;
  fromUid: string;
  toUid: string;
  card: Card;
  /** Set when the pass produced a winning hand. */
  winner: { uid: string; name: string } | null;
}

export function initialExchange(
  order: string[],
  hands: Record<string, Card[]>,
): ExchangeState {
  const incoming: Record<string, string | null> = {};
  for (const uid of order) incoming[uid] = null;
  return { order: order.slice(), turnIndex: 0, turnId: 0, hands, incoming };
}

export function currentPlayer(state: ExchangeState): string {
  return state.order[state.turnIndex];
}

export function nextPlayer(state: ExchangeState): string {
  return state.order[(state.turnIndex + 1) % state.order.length];
}

/** A hand wins when it is exactly 4 cards that all share one name. */
export function winningName(hand: Card[]): string | null {
  if (hand.length !== HAND_SIZE) return null;
  const name = hand[0].name;
  return hand.every((c) => c.name === name) ? name : null;
}

/**
 * Applies one pass. Pure: returns a new state and never mutates the input.
 * The passer's win is checked first, then the receiver's, so if a single pass
 * completes two hands at once the player who acted wins (deterministic).
 */
export function applyPass(
  state: ExchangeState,
  uid: string,
  cardId: string,
  expectedTurnId: number,
): PassResult {
  if (expectedTurnId !== state.turnId) {
    throw new GameError("failed-precondition", "That turn has already finished.");
  }
  const from = currentPlayer(state);
  if (uid !== from) {
    throw new GameError("permission-denied", "It is not your turn.");
  }
  const to = nextPlayer(state);
  const fromHand = state.hands[from] ?? [];
  if (fromHand.length < HAND_SIZE - 1 || fromHand.length > HAND_SIZE + 1) {
    throw new GameError("failed-precondition", "Hand size is out of range.");
  }
  if (fromHand.length < HAND_SIZE) {
    throw new GameError("failed-precondition", "You must hold at least 4 cards to pass.");
  }
  const card = fromHand.find((c) => c.id === cardId);
  if (!card) {
    throw new GameError("invalid-argument", "You can only pass a card you hold.");
  }

  const newFrom = fromHand.filter((c) => c.id !== cardId);
  const newTo = [...(state.hands[to] ?? []), card];
  const hands = { ...state.hands, [from]: newFrom, [to]: newTo };
  const incoming = { ...state.incoming, [from]: null, [to]: card.id };

  const next: ExchangeState = {
    order: state.order,
    turnIndex: (state.turnIndex + 1) % state.order.length,
    turnId: state.turnId + 1,
    hands,
    incoming,
  };

  const fromWin = winningName(newFrom);
  const toWin = fromWin ? null : winningName(newTo);
  const winner = fromWin
    ? { uid: from, name: fromWin }
    : toWin
      ? { uid: to, name: toWin }
      : null;

  return { state: next, fromUid: from, toUid: to, card, winner };
}

/** The card the server passes on behalf of a player whose time ran out. */
export function timeoutCard(
  hand: Card[],
  incomingId: string | null,
  policy: TimeoutPolicy,
  rng: Rng,
): Card {
  if (hand.length === 0) {
    throw new GameError("failed-precondition", "No cards to pass.");
  }
  if (policy === "passIncoming" && incomingId) {
    const incoming = hand.find((c) => c.id === incomingId);
    if (incoming) return incoming;
  }
  return hand[rng(hand.length)];
}
