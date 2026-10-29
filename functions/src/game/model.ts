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
 */

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
export type RoundStatus = "exchange" | "characters" | "revealed" | "aborted";

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
  settings: GameSettings;
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
  /** Players see the circular order until this time; passing starts after it. */
  introEndsAt: Timestamp;
  turnDeadline: Timestamp;
  movieNames: string[];
  handSizes: Record<string, number>;
  lastAction: LastAction | null;
  timeouts: Record<string, number>;
  winner: { uid: string; movie: string; points: number; at: Timestamp } | null;
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

export const roundKeyFor = (gameNo: number, roundNo: number) =>
  `g${gameNo}r${String(roundNo).padStart(2, "0")}`;

/** Seconds the circular order is shown before the first pass. */
export const INTRO_SECONDS = 5;
/** Seconds every non-winner sees their secret character before the reveal. */
export const REVEAL_DELAY_SECONDS = 7;
/** Network allowance after a deadline. Passes inside it count; timeouts start after it. */
export const DEADLINE_GRACE_MS = 1000;
/** Seconds the tied players have to vote on a tie-breaker. */
export const TIEBREAK_VOTE_SECONDS = 30;
/** Rooms untouched this long are closed by the cleanup job. */
export const ROOM_TTL_HOURS = 24;
