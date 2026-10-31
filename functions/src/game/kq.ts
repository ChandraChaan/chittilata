/**
 * King & Queen server operations. Rules: docs/KING_QUEEN_RULES.md.
 *
 * Firestore:
 *   rooms/{id}/kqRounds/{key}  public round state (no hidden roles until the end)
 *   rooms/{id}/kqRoles/{uid}   that player's own role (owner-only read)
 *   rooms/{id}/secrets/{key}   server-only: sealed chits and the role map
 */
import { DocumentReference, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import {
  GameError,
  KQ_DEFAULT_ROLES,
  KQ_MIN_PLAYERS,
  KqGuessRecord,
  kqChain,
  kqGuess as applyGuess,
  kqMergeRoles,
  KqRoleDef,
  KqState,
  kqStart,
  kqTimeoutTarget,
  randomId,
  RELAXED_TURN_SECONDS,
  shuffle,
  TURN_SECONDS_OPTIONS,
} from "../engine";
import { RoomDoc, roundKeyFor } from "./model";
import type { Deps } from "./ops";
import * as ops from "./ops";

export interface KqSettings {
  rounds: number;
  turnSeconds: number;
  roles: KqRoleDef[];
}

export type KqRoundStatus = "picking" | "guessing" | "revealed" | "aborted";

export interface KqRoundDoc {
  roundKey: string;
  gameNo: number;
  roundNo: number;
  status: KqRoundStatus;
  players: string[];
  /** Role names and points in chain order (public). */
  chain: string[];
  chainPoints: number[];
  chits: string[];
  picks: Record<string, string>;
  pickOpensAt: Timestamp;
  pickDeadline: Timestamp;
  step: number;
  guesser: string | null;
  /** uid -> chain index, for players whose role is final (public). */
  locked: Record<string, number>;
  /** Players known not to hold the role being searched for. */
  excluded: string[];
  turnId: number;
  timed: boolean;
  turnSeconds: number;
  guessOpensAt: Timestamp | null;
  turnDeadline: Timestamp | null;
  history: KqGuessRecord[];
  lastRequest: { uid: string; requestId: string } | null;
  /** Every player's final chain index, written only when the round ends. */
  revealedRoles: Record<string, number> | null;
  scores: Record<string, number> | null;
  abortedReason: string | null;
  startedAt: Timestamp;
  endedAt: Timestamp | null;
}

export interface KqRoleDoc {
  roundKey: string;
  index: number | null;
  name: string | null;
  points: number | null;
  updatedAt: Timestamp;
}

interface KqSecret {
  kqChits: Record<string, number>;
  kqRoles: Record<string, number>;
}

export const KQ_CEREMONY_SECONDS = 4;
export const KQ_PICK_SECONDS = 20;
/** Seconds the King is announced before the first guess. */
export const KQ_ANNOUNCE_SECONDS = 4;

export const kqRoundRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("kqRounds").doc(key) as DocumentReference<KqRoundDoc>;
const kqRoleRef = (db: Firestore, roomId: string, uid: string) =>
  db.collection("rooms").doc(roomId).collection("kqRoles").doc(uid) as DocumentReference<KqRoleDoc>;
const secretRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("secrets").doc(key) as DocumentReference<KqSecret>;
const auditRef = (db: Firestore, roomId: string) => db.collection("rooms").doc(roomId).collection("audit").doc();

const fail = (code: GameError["code"], msg: string): never => {
  throw new GameError(code, msg);
};

export function defaultKqSettings(): KqSettings {
  return { rounds: 7, turnSeconds: 20, roles: KQ_DEFAULT_ROLES.map((r) => ({ ...r })) };
}

export function mergeKqSettings(current: KqSettings, patch: unknown): KqSettings {
  if (typeof patch !== "object" || patch === null || Array.isArray(patch)) fail("invalid-argument", "Settings must be an object.");
  const p = patch as Record<string, unknown>;
  const next = { ...current };
  if ("rounds" in p) {
    const r = p.rounds;
    if (typeof r !== "number" || !Number.isInteger(r) || r < 1 || r > 30) fail("invalid-argument", "Rounds must be between 1 and 30.");
    next.rounds = r as number;
  }
  if ("turnSeconds" in p) {
    if (!TURN_SECONDS_OPTIONS.includes(p.turnSeconds as number)) fail("invalid-argument", "Unsupported turn timer.");
    next.turnSeconds = p.turnSeconds as number;
  }
  if ("roles" in p) next.roles = kqMergeRoles(current.roles, p.roles);
  return next;
}

/** Deals a King & Queen round: sealed role chits, empty roles, picking phase. */
export function startKqRoundTx(tx: Transaction, deps: Deps, roomId: string, room: RoomDoc) {
  const { db, now, rng } = deps;
  const settings = room.kqSettings ?? defaultKqSettings();
  const players = room.memberUids;
  const chain = kqChain(settings.roles, players.length);
  const roundNo = room.currentRound + 1;
  const key = roundKeyFor(room.gameNo, roundNo);
  const t = now();
  const ts = Timestamp.fromMillis(t);
  const kqChits: Record<string, number> = {};
  for (const index of shuffle(chain.map((_, i) => i), rng)) kqChits[`r${randomId(rng, 12)}`] = index;
  const chits = shuffle(Object.keys(kqChits), rng);
  const pickOpensAt = t + KQ_CEREMONY_SECONDS * 1000;
  const timed = settings.turnSeconds > 0;

  for (const uid of players) {
    tx.set(kqRoleRef(db, roomId, uid), { roundKey: key, index: null, name: null, points: null, updatedAt: ts });
  }
  tx.set(secretRef(db, roomId, key), { kqChits, kqRoles: {} });
  const round: KqRoundDoc = {
    roundKey: key,
    gameNo: room.gameNo,
    roundNo,
    status: "picking",
    players: players.slice(),
    chain: chain.map((r) => r.name),
    chainPoints: chain.map((r) => r.points),
    chits,
    picks: {},
    pickOpensAt: Timestamp.fromMillis(pickOpensAt),
    pickDeadline: Timestamp.fromMillis(pickOpensAt + KQ_PICK_SECONDS * 1000),
    step: 0,
    guesser: null,
    locked: {},
    excluded: [],
    turnId: 0,
    timed,
    turnSeconds: timed ? settings.turnSeconds : RELAXED_TURN_SECONDS,
    guessOpensAt: null,
    turnDeadline: null,
    history: [],
    lastRequest: null,
    revealedRoles: null,
    scores: null,
    abortedReason: null,
    startedAt: ts,
    endedAt: null,
  };
  tx.set(kqRoundRef(db, roomId, key), round);
  tx.update(ops.roomRef(db, roomId), {
    status: "playing",
    currentRound: roundNo,
    currentRoundKey: key,
    updatedAt: ts,
  });
  tx.create(auditRef(db, roomId), { type: "kqDeal", roundKey: key, sealed: kqChits, at: ts });
  return key;
}

async function loadKq(tx: Transaction, deps: Deps, uid: string, data: unknown) {
  const roomId = ops.str(data, "roomId");
  const roundKey = ops.str(data, "roundKey");
  const { room } = await ops.loadRoom(tx, deps.db, roomId);
  ops.requireMember(room, uid);
  if (room.mode !== "kingQueen") fail("failed-precondition", "This room is not playing King & Queen.");
  if (room.currentRoundKey !== roundKey) fail("failed-precondition", "That round is over.");
  const [roundSnap, secretSnap] = await Promise.all([
    tx.get(kqRoundRef(deps.db, roomId, roundKey)),
    tx.get(secretRef(deps.db, roomId, roundKey)),
  ]);
  const round = roundSnap.data();
  const secret = secretSnap.data();
  if (!round || !secret) fail("not-found", "Round not found.");
  return { roomId, roundKey, room, round: round!, secret: secret! };
}

/** Binds picks; when every chit is taken, the King is announced and guessing starts. */
function bindRoleChits(
  tx: Transaction,
  deps: Deps,
  roomId: string,
  round: KqRoundDoc,
  secret: KqSecret,
  assignments: [chitId: string, uid: string][],
  t: number,
  auto: boolean,
) {
  const { db } = deps;
  const ts = Timestamp.fromMillis(t);
  const picks = { ...round.picks };
  const kqRoles = { ...secret.kqRoles };
  for (const [chitId, uid] of assignments) {
    const index = secret.kqChits[chitId];
    picks[chitId] = uid;
    kqRoles[uid] = index;
    tx.update(kqRoleRef(db, roomId, uid), {
      index,
      name: round.chain[index],
      points: round.chainPoints[index],
      updatedAt: ts,
    });
  }
  tx.update(secretRef(db, roomId, round.roundKey), { kqRoles });
  const update: Record<string, unknown> = { picks };
  if (Object.keys(picks).length === round.chits.length) {
    const state = kqStart(round.players, round.chain, kqRoles);
    const opens = t + KQ_ANNOUNCE_SECONDS * 1000;
    Object.assign(update, {
      status: "guessing",
      step: 0,
      guesser: state.guesser,
      turnId: 0,
      guessOpensAt: Timestamp.fromMillis(opens),
      turnDeadline: Timestamp.fromMillis(opens + round.turnSeconds * 1000),
    });
  }
  tx.update(kqRoundRef(db, roomId, round.roundKey), update);
  tx.create(auditRef(db, roomId), {
    type: auto ? "kqAutoPick" : "kqPick",
    roundKey: round.roundKey,
    picks: Object.fromEntries(assignments),
    at: ts,
  });
}

/** A player picks one folded role chit and privately learns their role. */
export async function kqPickChit(deps: Deps, uid: string, data: unknown) {
  const chitId = ops.str(data, "chitId");
  return deps.db.runTransaction(async (tx) => {
    const { roomId, round, secret } = await loadKq(tx, deps, uid, data);
    if (!round.players.includes(uid)) fail("permission-denied", "You are not playing this round.");
    const index = secret.kqChits[chitId];
    if (round.picks[chitId] === uid) {
      return { duplicate: true, role: { index, name: round.chain[index], points: round.chainPoints[index] } };
    }
    if (round.status !== "picking") fail("failed-precondition", "Picking has finished.");
    const t = deps.now();
    if (t < round.pickOpensAt.toMillis()) fail("failed-precondition", "The chits are still being shuffled.");
    if (index === undefined) fail("invalid-argument", "That chit is not on the table.");
    if (round.picks[chitId]) fail("already-exists", "Someone else picked that chit first.");
    if (Object.values(round.picks).includes(uid)) fail("failed-precondition", "You already picked your chit.");
    bindRoleChits(tx, deps, roomId, round, secret, [[chitId, uid]], t, false);
    return { duplicate: false, role: { index, name: round.chain[index], points: round.chainPoints[index] } };
  });
}

/** Hands out the remaining chits at random, once [ops.requirePlayFor] allows it. */
export async function kqAutoPick(deps: Deps, uid: string, data: unknown) {
  return deps.db.runTransaction(async (tx) => {
    const { roomId, round, secret } = await loadKq(tx, deps, uid, data);
    if (round.status !== "picking") return { assigned: 0 };
    const t = deps.now();
    const picked = new Set(Object.values(round.picks));
    const late = round.players.filter((p) => !picked.has(p));
    await ops.requirePlayFor(tx, deps.db, roomId, late, round.pickDeadline.toMillis(), t);
    const free = shuffle(round.chits.filter((c) => !round.picks[c]), deps.rng);
    const assignments = round.players.filter((p) => !picked.has(p)).map((p) => [free.pop()!, p] as [string, string]);
    bindRoleChits(tx, deps, roomId, round, secret, assignments, t, true);
    return { assigned: assignments.length };
  });
}

/** Applies a guess (player or timeout) inside a transaction. */
async function guessTx(
  deps: Deps,
  data: unknown,
  actor: { kind: "guess"; uid: string; target: string; requestId: string } | { kind: "timeout"; uid: string },
) {
  const { db, now, rng } = deps;
  const turnId = ops.int(data, "turnId");
  return db.runTransaction(async (tx) => {
    const { roomId, room, round, secret } = await loadKq(tx, deps, actor.uid, data);
    if (actor.kind === "guess" && round.lastRequest?.requestId === actor.requestId && round.lastRequest.uid === actor.uid) {
      return { duplicate: true, done: round.status === "revealed" };
    }
    if (round.status !== "guessing") fail("failed-precondition", "Guessing has not started or is over.");
    if (round.turnId !== turnId) fail("failed-precondition", "That turn has already finished.");
    const t = now();
    if (t < round.guessOpensAt!.toMillis()) fail("failed-precondition", "The King is still being announced.");
    // A late guesser can still guess: nothing is auto-played for them.
    if (actor.kind === "timeout") {
      await ops.requirePlayFor(tx, db, roomId, [round.guesser!], round.turnDeadline!.toMillis(), t);
    }

    const before: KqState = {
      chain: round.chain,
      roles: secret.kqRoles,
      players: round.players,
      step: round.step,
      guesser: round.guesser!,
      locked: Object.keys(round.locked),
      excluded: round.excluded,
      turnId: round.turnId,
      history: round.history,
      done: false,
    };
    const target = actor.kind === "guess" ? actor.target : kqTimeoutTarget(before, rng);
    const after = applyGuess(before, actor.uid, target, turnId, actor.kind === "guess" ? "guess" : "timeout");
    const ts = Timestamp.fromMillis(t);

    // Privately tell players whose role changed (only wrong guesses swap).
    for (const p of round.players) {
      if (after.roles[p] !== before.roles[p]) {
        const index = after.roles[p];
        tx.update(kqRoleRef(db, roomId, p), {
          index,
          name: round.chain[index],
          points: round.chainPoints[index],
          updatedAt: ts,
        });
      }
    }
    tx.update(secretRef(db, roomId, round.roundKey), { kqRoles: after.roles });

    const update: Record<string, unknown> = {
      step: after.step,
      guesser: after.done ? null : after.guesser,
      locked: Object.fromEntries(after.locked.map((p) => [p, after.roles[p]])),
      excluded: after.excluded,
      turnId: after.turnId,
      history: after.history,
      turnDeadline: Timestamp.fromMillis(t + round.turnSeconds * 1000),
      lastRequest: actor.kind === "guess" ? { uid: actor.uid, requestId: actor.requestId } : round.lastRequest,
    };
    if (after.done) {
      // Round over: reveal every role and score exactly once (guarded by status).
      const scores = Object.fromEntries(round.players.map((p) => [p, round.chainPoints[after.roles[p]]]));
      const king = round.players.find((p) => after.roles[p] === 0)!;
      Object.assign(update, { status: "revealed", revealedRoles: after.roles, scores, endedAt: ts, turnDeadline: null });
      const totals = { ...room.totals };
      for (const [p, pts] of Object.entries(scores)) totals[p] = (totals[p] ?? 0) + pts;
      const kingWins = { ...(room.kingWins ?? {}) };
      kingWins[king] = (kingWins[king] ?? 0) + 1;
      const roomUpdate: Record<string, unknown> = { totals, kingWins, updatedAt: ts };
      const settings = room.kqSettings ?? defaultKqSettings();
      if (room.currentRound >= settings.rounds) {
        roomUpdate.status = "finished";
        roomUpdate.final = ops.standingsFor({ ...room, totals, kingWins });
      }
      tx.update(ops.roomRef(db, roomId), roomUpdate);
    }
    tx.update(kqRoundRef(db, roomId, round.roundKey), update);
    tx.create(auditRef(db, roomId), {
      type: actor.kind === "guess" ? "kqGuess" : "kqTimeout",
      roundKey: round.roundKey,
      turnId,
      by: actor.uid,
      target,
      steps: after.history.slice(round.history.length),
      at: ts,
    });
    return { duplicate: false, done: after.done };
  });
}

export async function kqGuess(deps: Deps, uid: string, data: unknown) {
  return guessTx(deps, data, {
    kind: "guess",
    uid,
    target: ops.str(data, "targetUid", 128),
    requestId: ops.str(data, "requestId"),
  });
}

/** Another member guesses at random for a late guesser, once [ops.requirePlayFor] allows it. */
export async function kqClaimTimeout(deps: Deps, uid: string, data: unknown) {
  return guessTx(deps, data, { kind: "timeout", uid });
}

/** Room fields when a member leaves a King & Queen game mid-round. */
export async function kqLeaveEffects(tx: Transaction, deps: Deps, roomId: string, room: RoomDoc, uid: string, members: string[]) {
  const out: Record<string, unknown> = {};
  const key = room.currentRoundKey;
  if (room.status !== "playing" || !key) return { out, apply: () => {} };
  const round = (await tx.get(kqRoundRef(deps.db, roomId, key))).data();
  const apply = () => {
    if (round && (round.status === "picking" || round.status === "guessing") && members.length > 0) {
      tx.update(kqRoundRef(deps.db, roomId, key), {
        status: "aborted",
        abortedReason: `${room.players[uid].name} left the game.`,
        guesser: null,
        endedAt: Timestamp.fromMillis(deps.now()),
      });
    }
  };
  if (members.length > 0 && members.length < KQ_MIN_PLAYERS) {
    out.status = "finished";
    out.final = ops.standingsFor({ ...room, players: { ...room.players, [uid]: { ...room.players[uid], left: true } } });
  }
  return { out, apply };
}

export async function kqCurrentRound(tx: Transaction, db: Firestore, roomId: string, key: string | null) {
  return key ? (await tx.get(kqRoundRef(db, roomId, key))).data() ?? null : null;
}
