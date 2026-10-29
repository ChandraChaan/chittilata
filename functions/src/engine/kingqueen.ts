/**
 * King & Queen — pure rules engine. Specification: docs/KING_QUEEN_RULES.md.
 * No Firebase here; the server wraps these transitions in transactions.
 */
import { GameError, Rng } from "./types";

export const KQ_MIN_PLAYERS = 4;
export const KQ_MAX_PLAYERS = 10;

export interface KqRoleDef {
  /** Stable identifier; never shown to players. */
  key: string;
  name: string;
  points: number;
  /** Core roles are always used and cannot be renamed. */
  core: boolean;
}

/** The full catalogue in chain order (spec §1). */
export const KQ_DEFAULT_ROLES: KqRoleDef[] = [
  { key: "king", name: "King", points: 1000, core: true },
  { key: "queen", name: "Queen", points: 800, core: true },
  { key: "minister", name: "Minister", points: 700, core: false },
  { key: "commander", name: "Commander", points: 600, core: false },
  { key: "police", name: "Police", points: 500, core: true },
  { key: "merchant", name: "Merchant", points: 400, core: false },
  { key: "poet", name: "Poet", points: 300, core: false },
  { key: "farmer", name: "Farmer", points: 200, core: false },
  { key: "jester", name: "Jester", points: 150, core: false },
  { key: "thief", name: "Thief", points: 100, core: true },
];

/** Optional roles join in this order as players increase (spec §1). */
const OPTIONAL_PRIORITY = ["minister", "commander", "merchant", "poet", "farmer", "jester"];

/** The chain for `players` players, in catalogue order. */
export function kqChain(catalogue: KqRoleDef[], players: number): KqRoleDef[] {
  if (players < KQ_MIN_PLAYERS || players > KQ_MAX_PLAYERS) {
    throw new GameError(
      "failed-precondition",
      `King & Queen needs ${KQ_MIN_PLAYERS}-${KQ_MAX_PLAYERS} players (you have ${players}).`,
    );
  }
  const wanted = new Set([
    ...catalogue.filter((r) => r.core).map((r) => r.key),
    ...OPTIONAL_PRIORITY.slice(0, players - KQ_MIN_PLAYERS),
  ]);
  const chain = catalogue.filter((r) => wanted.has(r.key));
  if (chain.length !== players) {
    throw new GameError("failed-precondition", "The role list does not match the player count.");
  }
  return chain;
}

export interface KqGuessRecord {
  step: number;
  guesser: string;
  target: string;
  correct: boolean;
  /** forced = only one candidate left; timeout = the server guessed. */
  kind: "guess" | "forced" | "timeout";
}

export interface KqState {
  /** Role names in chain order (public). */
  chain: string[];
  /** uid -> index into chain (secret). */
  roles: Record<string, number>;
  players: string[];
  step: number;
  guesser: string;
  locked: string[];
  excluded: string[];
  turnId: number;
  history: KqGuessRecord[];
  done: boolean;
}

/** Starts guessing: the King (chain index 0) is the first guesser. */
export function kqStart(players: string[], chain: string[], roles: Record<string, number>): KqState {
  const indices = players.map((p) => roles[p]).sort((a, b) => a - b);
  if (players.length !== chain.length || indices.some((v, i) => v !== i)) {
    throw new GameError("failed-precondition", "Roles must be a permutation of the chain.");
  }
  const king = players.find((p) => roles[p] === 0)!;
  return { chain, roles: { ...roles }, players: players.slice(), step: 0, guesser: king, locked: [], excluded: [], turnId: 0, history: [], done: false };
}

export function kqCandidates(s: KqState): string[] {
  if (s.done) return [];
  const out = new Set([...s.locked, s.guesser, ...s.excluded]);
  return s.players.filter((p) => !out.has(p));
}

/** Applies one guess (or timeout guess), then any forced resolutions. Pure. */
export function kqGuess(
  state: KqState,
  uid: string,
  target: string,
  expectedTurnId: number,
  kind: "guess" | "timeout" = "guess",
): KqState {
  if (state.done) throw new GameError("failed-precondition", "The round is over.");
  if (expectedTurnId !== state.turnId) throw new GameError("failed-precondition", "That turn has already finished.");
  if (kind === "guess" && uid !== state.guesser) throw new GameError("permission-denied", "It is not your turn to guess.");
  if (!kqCandidates(state).includes(target)) {
    throw new GameError("invalid-argument", "You can't pick that player.");
  }
  let s = applyOne(state, target, kind);
  // Forced resolution: a single candidate must hold the target role.
  while (!s.done) {
    const c = kqCandidates(s);
    if (c.length !== 1) break;
    s = applyOne(s, c[0], "forced");
  }
  return s;
}

function applyOne(state: KqState, target: string, kind: KqGuessRecord["kind"]): KqState {
  const s: KqState = {
    ...state,
    roles: { ...state.roles },
    locked: state.locked.slice(),
    excluded: state.excluded.slice(),
    history: state.history.slice(),
    turnId: state.turnId + 1,
  };
  const g = s.guesser;
  const correct = s.roles[target] === s.step + 1;
  s.history.push({ step: s.step, guesser: g, target, correct, kind });
  if (correct) {
    s.locked.push(g);
    s.guesser = target;
    s.step += 1;
    s.excluded = [];
    if (s.step === s.chain.length - 1) {
      // The last role (Thief) is final as soon as it is found.
      s.locked.push(target);
      s.done = true;
    }
  } else {
    const gRole = s.roles[g];
    s.roles[g] = s.roles[target];
    s.roles[target] = gRole;
    s.excluded.push(g);
    s.guesser = target;
  }
  return s;
}

/** A uniformly random candidate, used when the guesser runs out of time. */
export function kqTimeoutTarget(s: KqState, rng: Rng): string {
  const c = kqCandidates(s);
  if (c.length === 0) throw new GameError("failed-precondition", "Nobody left to guess.");
  return c[rng(c.length)];
}

/** Points for each player's final role. */
export function kqScores(s: KqState, catalogue: KqRoleDef[]): Record<string, number> {
  const points = new Map(catalogue.map((r) => [r.name, r.points]));
  const out: Record<string, number> = {};
  for (const p of s.players) out[p] = points.get(s.chain[s.roles[p]]) ?? 0;
  return out;
}

/** Validates and merges a host's role edits (names of optional roles, all points). */
export function kqMergeRoles(current: KqRoleDef[], patch: unknown): KqRoleDef[] {
  if (!Array.isArray(patch)) throw new GameError("invalid-argument", "Roles must be a list.");
  const byKey = new Map((patch as unknown[]).map((r) => [((r ?? {}) as Record<string, unknown>).key, r as Record<string, unknown>]));
  const next = current.map((role) => {
    const p = byKey.get(role.key);
    if (!p) return role;
    const points = p.points;
    if (typeof points !== "number" || !Number.isInteger(points) || points < 0 || points > 5000) {
      throw new GameError("invalid-argument", "Role points must be between 0 and 5000.");
    }
    let name = role.name;
    if (!role.core && p.name !== undefined) {
      if (typeof p.name !== "string") throw new GameError("invalid-argument", "Role name must be text.");
      name = p.name.replace(/\s+/g, " ").trim();
      if (!name || name.length > 16) throw new GameError("invalid-argument", "Role names must be 1-16 characters.");
    }
    return { ...role, name, points };
  });
  const names = new Set(next.map((r) => r.name.toLowerCase()));
  if (names.size !== next.length) throw new GameError("invalid-argument", "Role names must be different.");
  return next;
}
