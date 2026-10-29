import type { Timestamp } from "firebase-admin/firestore";
import type { Card, CharacterDef, GameSettings, Standing } from "../engine";

/**
 * Firestore layout (see docs/ARCHITECTURE.md):
 *   roomCodes/{code}            code -> roomId lookup (server only)
 *   rooms/{roomId}              public room state (members only)
 *   rooms/{roomId}/rounds/{key} public round state; secrets appear only after reveal
 *   rooms/{roomId}/hands/{uid}  private hand + character (owner only)
 *   rooms/{roomId}/presence/{uid} heartbeat written by the owner
 *   rooms/{roomId}/audit/{id}   server-only debug log with card details
 *   rooms/{roomId}/secrets/{key} server-only: undealt slips and sealed character chits
 */

export type GameMode = "movie" | "kingQueen";

export type RoomStatus = "lobby" | "playing" | "tiebreakVote" | "finished" | "closed";

/**
 * A tie for King or Queen after the last round. The tied players vote; the
 * tie-breaker round is played only if all of them accept.
 */
export interface TiebreakState {
  title: "King" | "Queen";
  uids: string[];
  votes: Record<string, boolean>;
  deadline: Timestamp;
  stage: "vote" | "playing" | "declined" | "done" | "cancelled";
}
export type RoundStatus = "picking" | "exchange" | "characters" | "revealed" | "aborted";

export interface PlayerInfo {
  name: string;
  joinedAt: number;
  ready: boolean;
  left: boolean;
}

export interface RoomDoc {
  code: string;
  hostUid: string;
  status: RoomStatus;
  /** Active members in join order. Drives read access in security rules. */
  memberUids: string[];
  /** Everyone who has played this game, including players who left. */
  players: Record<string, PlayerInfo>;
  banned: string[];
  /** Absent on rooms created before modes existed: treated as "movie". */
  mode?: GameMode;
  settings: GameSettings;
  /** King & Queen settings (rounds, timer, role points). */
  kqSettings?: { rounds: number; turnSeconds: number; roles: { key: string; name: string; points: number; core: boolean }[] };
  /** King & Queen: rounds each player finished as King (the tie-break key). */
  kingWins?: Record<string, number>;
  gameNo: number;
  currentRound: number;
  currentRoundKey: string | null;
  totals: Record<string, number>;
  movieWins: Record<string, number>;
  usedNames: string[];
  final: Standing[] | null;
  tiebreak: TiebreakState | null;
  /** Points each tied player scored in the tie-breaker round (not in totals). */
  tiebreakScores: Record<string, number> | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface LastAction {
  type: "pass" | "timeout";
  fromUid: string;
  toUid: string;
  turnId: number;
  requestId: string | null;
  at: Timestamp;
}

export interface RoundDoc {
  roundKey: string;
  gameNo: number;
  roundNo: number;
  /** A tie-breaker round among tied players; its points never reach totals. */
  tiebreak: boolean;
  status: RoundStatus;
  order: string[];
  turnIndex: number;
  turnId: number;
  currentUid: string;
  nextUid: string;
  timed: boolean;
  turnSeconds: number;
  /**
   * Folded movie chits on the table (opaque ids, no contents). Each player
   * picks 4; a picked chit is bound to the next slip of that player's
   * secretly dealt hand, so the fair-deal rules always hold.
   */
  chits: string[];
  /** chitId -> uid of the player who picked it. */
  picks: Record<string, string>;
  /** Picking opens after the folding/shuffling animation on every phone. */
  pickOpensAt: Timestamp;
  /** After this, any member may ask the server to finish the picks at random. */
  pickDeadline: Timestamp;
  /** Players see the circular order until this time; passing starts after it. */
  introEndsAt: Timestamp;
  turnDeadline: Timestamp;
  movieNames: string[];
  handSizes: Record<string, number>;
  lastAction: LastAction | null;
  timeouts: Record<string, number>;
  winner: { uid: string; movie: string; points: number; at: Timestamp } | null;
  /** Folded character chits (opaque ids); one per non-winner. */
  charChits: string[];
  /** chitId -> uid. */
  charPicks: Record<string, string>;
  charPickOpensAt: Timestamp | null;
  charPickDeadline: Timestamp | null;
  /** Set once every character chit is picked; the reveal may happen after it. */
  revealAt: Timestamp | null;
  revealedHands: Record<string, Card[]> | null;
  characters: Record<string, CharacterDef> | null;
  scores: Record<string, number> | null;
  abortedReason: string | null;
  startedAt: Timestamp;
  endedAt: Timestamp | null;
}

export interface HandDoc {
  roundKey: string;
  cards: Card[];
  incomingCardId: string | null;
  character: CharacterDef | null;
  updatedAt: Timestamp;
}

/** Server-only per-round secrets. Clients can never read this document. */
export interface SecretDoc {
  /** uid -> that player's not-yet-picked slips (already fairly dealt). */
  deal: Record<string, Card[]>;
  /** movie chitId -> card id it was bound to (for idempotent retries). */
  bound: Record<string, string>;
  /** character chitId -> sealed character. */
  characters: Record<string, CharacterDef>;
}

export const roundKeyFor = (gameNo: number, roundNo: number) =>
  `g${gameNo}r${String(roundNo).padStart(2, "0")}`;

/** Seconds of the create/fold/shuffle/scatter animation before picking opens. */
export const CHIT_CEREMONY_SECONDS = 4;
/** Seconds players have to pick their movie chits. */
export const PICK_SECONDS = 25;
/** Seconds of winner celebration before character chits can be picked. */
export const CHAR_CEREMONY_SECONDS = 4;
/** Seconds eligible players have to pick a character chit. */
export const CHAR_PICK_SECONDS = 20;
/** Seconds the circular order is shown before the first pass. */
export const INTRO_SECONDS = 5;
/** Seconds everyone looks at their own character before the public reveal. */
export const REVEAL_DELAY_SECONDS = 5;
/** Network allowance after a deadline. Passes inside it count; timeouts start after it. */
export const DEADLINE_GRACE_MS = 1000;
/** Seconds the tied players have to vote on a tie-breaker. */
export const TIEBREAK_VOTE_SECONDS = 30;
/** Rooms untouched this long are closed by the cleanup job. */
export const ROOM_TTL_HOURS = 24;
