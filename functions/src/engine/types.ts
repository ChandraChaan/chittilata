/** A physical card. Two cards may share a name but never an id. */
export interface Card {
  id: string;
  name: string;
}

export type Category = "telugu" | "indian" | "hollywood" | "custom" | "mixed";
export type Difficulty = "easy" | "normal" | "challenging";

/**
 * What happens when the current player's turn deadline passes.
 * - passIncoming: the card they just received moves on (a random card if
 *   they had no incoming card, i.e. the round starter's first turn).
 * - passRandom: a uniformly random card from their hand moves on.
 * Neither policy ever looks at which card would help the player.
 */
export type TimeoutPolicy = "passIncoming" | "passRandom";

export interface CharacterDef {
  name: string;
  points: number;
}

export interface GameSettings {
  category: Category;
  customNames: string[];
  rounds: number;
  /** 0 = relaxed mode (no visible timer, auto-pass after RELAXED_TURN_SECONDS). */
  turnSeconds: number;
  difficulty: Difficulty;
  timeoutPolicy: TimeoutPolicy;
  winPoints: number;
  characters: CharacterDef[];
}

/** Returns an integer in [0, maxExclusive). */
export type Rng = (maxExclusive: number) => number;

export class GameError extends Error {
  constructor(
    public readonly code: GameErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "GameError";
  }
}

export type GameErrorCode =
  | "invalid-argument"
  | "failed-precondition"
  | "permission-denied"
  | "not-found"
  | "already-exists"
  | "resource-exhausted";

export const MIN_PLAYERS = 3;
export const MAX_PLAYERS = 10;
export const HAND_SIZE = 4;
export const COPIES_PER_NAME = 4;
export const RELAXED_TURN_SECONDS = 300;
