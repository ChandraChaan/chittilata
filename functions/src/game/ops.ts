import {
  DocumentReference,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {
  applyPass,
  buildDeck,
  charactersFor,
  Card,
  cleanPlayerName,
  dealHands,
  defaultSettings,
  eligibleNames,
  ExchangeState,
  GameError,
  HAND_SIZE,
  MAX_PLAYERS,
  mergeSettings,
  MIN_PLAYERS,
  pickNames,
  randomId,
  rankPlayers,
  RELAXED_TURN_SECONDS,
  Rng,
  roomCode,
  roundScores,
  shuffle,
  timeoutCard,
  titleTie,
  validateForStart,
  KQ_DEFAULT_ROLES,
  kqChain,
} from "../engine";
import * as kq from "./kq";
import {
  CHAR_CEREMONY_SECONDS,
  CHAR_PICK_SECONDS,
  CHIT_CEREMONY_SECONDS,
  DEADLINE_GRACE_MS,
  HandDoc,
  INTRO_SECONDS,
  LastAction,
  OFFLINE_AFTER_MS,
  PICK_SECONDS,
  PLAY_FOR_AFTER_MS,
  REVEAL_DELAY_SECONDS,
  RoomDoc,
  roundKeyFor,
  RoundDoc,
  SecretDoc,
  TIEBREAK_VOTE_SECONDS,
  TiebreakState,
} from "./model";

export interface Deps {
  db: Firestore;
  now: () => number;
  rng: Rng;
}

export const fail = (code: GameError["code"], msg: string): never => {
  throw new GameError(code, msg);
};

// ---------- helpers ----------

export const roomRef = (db: Firestore, roomId: string) =>
  db.collection("rooms").doc(roomId) as DocumentReference<RoomDoc>;
const roundRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("rounds").doc(key) as DocumentReference<RoundDoc>;
const handRef = (db: Firestore, roomId: string, uid: string) =>
  db.collection("rooms").doc(roomId).collection("hands").doc(uid) as DocumentReference<HandDoc>;
const secretRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("secrets").doc(key) as DocumentReference<SecretDoc>;
const auditRef = (db: Firestore, roomId: string) =>
  db.collection("rooms").doc(roomId).collection("audit").doc();
const presenceRef = (db: Firestore, roomId: string, uid: string) =>
  db.collection("rooms").doc(roomId).collection("presence").doc(uid);

/**
 * Nothing is played for a late player automatically. Another member may play
 * for the late players only once they are PLAY_FOR_AFTER_MS past the deadline,
 * or sooner if every one of them is offline. Reads only, so it can run before
 * a transaction's writes.
 */
export async function requirePlayFor(
  tx: Transaction,
  db: Firestore,
  roomId: string,
  late: string[],
  deadline: number,
  t: number,
) {
  if (t <= deadline + DEADLINE_GRACE_MS) fail("failed-precondition", "There is still time left.");
  if (t > deadline + PLAY_FOR_AFTER_MS) return;
  const snaps = await Promise.all(late.map((u) => tx.get(presenceRef(db, roomId, u))));
  const offline = snaps.every((s) => {
    const seen = s.data()?.lastSeen as Timestamp | undefined;
    return !seen || seen.toMillis() < t - OFFLINE_AFTER_MS;
  });
  if (!offline) fail("failed-precondition", "Give them a little longer, or send a nudge.");
}

export function str(data: unknown, field: string, max = 64): string {
  const v = (data as Record<string, unknown> | null)?.[field];
  if (typeof v !== "string" || !v || v.length > max) fail("invalid-argument", `Missing ${field}.`);
  return v as string;
}

export function int(data: unknown, field: string): number {
  const v = (data as Record<string, unknown> | null)?.[field];
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0) fail("invalid-argument", `Missing ${field}.`);
  return v as number;
}

export async function loadRoom(tx: Transaction, db: Firestore, roomId: string) {
  const ref = roomRef(db, roomId);
  const snap = await tx.get(ref);
  if (!snap.exists) fail("not-found", "This room no longer exists.");
  const room = snap.data() as RoomDoc;
  if (room.status === "closed") fail("not-found", "This room has closed.");
  return { ref, room };
}

export function requireMember(room: RoomDoc, uid: string) {
  if (!room.memberUids.includes(uid)) fail("permission-denied", "You are not in this room.");
}

export function requireHost(room: RoomDoc, uid: string) {
  requireMember(room, uid);
  if (room.hostUid !== uid) fail("permission-denied", "Only the host can do that.");
}

/** Host passes to the longest-standing remaining member. */
function migrateHost(room: RoomDoc): string {
  return room.memberUids.includes(room.hostUid) ? room.hostUid : (room.memberUids[0] ?? room.hostUid);
}

export function standingsFor(room: RoomDoc) {
  return rankPlayers(
    Object.entries(room.players).map(([uid, p]) => ({
      uid,
      name: p.name,
      total: room.totals[uid] ?? 0,
      // Second ranking key: movie wins, or rounds finished as King.
      movieWins: (room.mode === "kingQueen" ? room.kingWins?.[uid] : room.movieWins[uid]) ?? 0,
      left: p.left,
      ...(room.tiebreakScores?.[uid] !== undefined ? { tiebreak: room.tiebreakScores[uid] } : {}),
    })),
  );
}

/**
 * Room fields for the end of the scheduled rounds: either the final result,
 * or (once per game) a vote on a tie-breaker when a title is shared.
 */
function endOfGameUpdate(room: RoomDoc, t: number): Record<string, unknown> {
  const final = standingsFor(room);
  const tie = room.tiebreak ? null : titleTie(final);
  if (!tie) return { status: "finished", final };
  const tiebreak: TiebreakState = {
    title: tie.title,
    uids: tie.uids,
    votes: {},
    deadline: Timestamp.fromMillis(t + TIEBREAK_VOTE_SECONDS * 1000),
    stage: "vote",
  };
  return { status: "tiebreakVote", final, tiebreak };
}

// ---------- lobby ----------

export async function createRoom(deps: Deps, uid: string, data: unknown) {
  const name = cleanPlayerName((data as Record<string, unknown> | null)?.name);
  const rawMode = (data as Record<string, unknown> | null)?.mode ?? "movie";
  if (rawMode !== "movie" && rawMode !== "kingQueen") fail("invalid-argument", "Unknown game mode.");
  const mode = rawMode as "movie" | "kingQueen";
  const { db, now, rng } = deps;
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = roomCode(rng);
    const codeRef = db.collection("roomCodes").doc(code);
    const ref = db.collection("rooms").doc() as DocumentReference<RoomDoc>;
    const created = await db.runTransaction(async (tx) => {
      if ((await tx.get(codeRef)).exists) return false;
      const ts = Timestamp.fromMillis(now());
      const room: RoomDoc = {
        code,
        hostUid: uid,
        status: "lobby",
        memberUids: [uid],
        players: { [uid]: { name, joinedAt: now(), ready: true, left: false } },
        banned: [],
        mode,
        settings: defaultSettings(),
        kqSettings: kq.defaultKqSettings(),
        kingWins: {},
        gameNo: 1,
        currentRound: 0,
        currentRoundKey: null,
        totals: {},
        movieWins: {},
        usedNames: [],
        final: null,
        tiebreak: null,
        tiebreakScores: null,
        createdAt: ts,
        updatedAt: ts,
      };
      tx.create(ref, room);
      tx.create(codeRef, { roomId: ref.id, createdAt: ts });
      return true;
    });
    if (created) return { roomId: ref.id, code, mode };
  }
  return fail("resource-exhausted", "Could not allocate a room code. Try again.");
}

export async function joinRoom(deps: Deps, uid: string, data: unknown) {
  const { db, now } = deps;
  const code = str(data, "code", 12).trim().toUpperCase();
  const name = cleanPlayerName((data as Record<string, unknown>).name);
  const codeSnap = await db.collection("roomCodes").doc(code).get();
  if (!codeSnap.exists) fail("not-found", "No room with that code.");
  const roomId = codeSnap.get("roomId") as string;

  await db.runTransaction(async (tx) => {
    const { ref, room } = await loadRoom(tx, db, roomId);
    if (room.banned.includes(uid)) fail("permission-denied", "The host removed you from this room.");
    if (room.memberUids.includes(uid)) {
      // Rejoining (same device/account): keep seat, refresh name only in lobby.
      if (room.status === "lobby" && room.players[uid].name !== name) {
        tx.update(ref, { [`players.${uid}.name`]: name, updatedAt: Timestamp.fromMillis(now()) });
      }
      return;
    }
    if (room.status !== "lobby") fail("failed-precondition", "This game has already started.");
    if (room.memberUids.length >= MAX_PLAYERS) fail("resource-exhausted", "This room is full.");
    const taken = room.memberUids.some((m) => room.players[m].name.toLowerCase() === name.toLowerCase());
    if (taken) fail("already-exists", "Someone in this room already uses that name.");
    tx.update(ref, {
      memberUids: [...room.memberUids, uid],
      [`players.${uid}`]: { name, joinedAt: now(), ready: false, left: false },
      updatedAt: Timestamp.fromMillis(now()),
    });
  });
  return { roomId, code };
}

export async function setReady(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const ready = (data as Record<string, unknown>).ready === true;
  await deps.db.runTransaction(async (tx) => {
    const { ref, room } = await loadRoom(tx, deps.db, roomId);
    requireMember(room, uid);
    if (room.status !== "lobby") fail("failed-precondition", "The game has already started.");
    tx.update(ref, { [`players.${uid}.ready`]: ready, updatedAt: Timestamp.fromMillis(deps.now()) });
  });
  return { ok: true };
}

export async function updateSettings(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const patch = (data as Record<string, unknown>).settings;
  return deps.db.runTransaction(async (tx) => {
    const { ref, room } = await loadRoom(tx, deps.db, roomId);
    requireHost(room, uid);
    if (room.status !== "lobby") fail("failed-precondition", "Settings are locked once the game starts.");
    if (room.mode === "kingQueen") {
      const kqSettings = kq.mergeKqSettings(room.kqSettings ?? kq.defaultKqSettings(), (data as Record<string, unknown>).kqSettings);
      tx.update(ref, { kqSettings, updatedAt: Timestamp.fromMillis(deps.now()) });
      return { kqSettings };
    }
    const settings = mergeSettings(room.settings, patch);
    tx.update(ref, { settings, updatedAt: Timestamp.fromMillis(deps.now()) });
    return { settings };
  });
}

export async function kickPlayer(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const target = str(data, "uid", 128);
  await deps.db.runTransaction(async (tx) => {
    const { ref, room } = await loadRoom(tx, deps.db, roomId);
    requireHost(room, uid);
    if (room.status !== "lobby") fail("failed-precondition", "Players can only be removed in the lobby.");
    if (target === uid) fail("invalid-argument", "Use Leave to exit the room.");
    if (!room.memberUids.includes(target)) return;
    const players = { ...room.players };
    delete players[target];
    tx.update(ref, {
      memberUids: room.memberUids.filter((m) => m !== target),
      players,
      banned: [...room.banned, target],
      updatedAt: Timestamp.fromMillis(deps.now()),
    });
  });
  return { ok: true };
}

export async function leaveRoom(deps: Deps, uid: string, data: unknown) {
  const { db, now } = deps;
  const roomId = str(data, "roomId");
  await db.runTransaction(async (tx) => {
    const ref = roomRef(db, roomId);
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const room = snap.data() as RoomDoc;
    if (!room.memberUids.includes(uid)) return;
    const isKq = room.mode === "kingQueen";
    const round =
      !isKq && room.status === "playing" && room.currentRoundKey
        ? ((await tx.get(roundRef(db, roomId, room.currentRoundKey))).data() as RoundDoc | undefined)
        : undefined;

    const ts = Timestamp.fromMillis(now());
    const members = room.memberUids.filter((m) => m !== uid);
    const kqEffects = isKq ? await kq.kqLeaveEffects(tx, deps, roomId, room, uid, members) : null;
    const next: Partial<RoomDoc> & Record<string, unknown> = { memberUids: members, updatedAt: ts };

    if (members.length === 0) {
      next.status = "closed";
      tx.delete(db.collection("roomCodes").doc(room.code));
    } else if (room.status === "lobby") {
      const players = { ...room.players };
      delete players[uid];
      next.players = players;
    } else {
      next[`players.${uid}.left`] = true;
    }
    next.hostUid = migrateHost({ ...room, memberUids: members });

    if (round && (round.status === "exchange" || round.status === "picking") && members.length > 0) {
      // The leaver's cards cannot keep circulating, so the round is void.
      tx.update(roundRef(db, roomId, round.roundKey), {
        status: "aborted",
        abortedReason: `${room.players[uid].name} left the game.`,
        endedAt: ts,
      });
    }
    const tb = room.tiebreak;
    const tiedLeaver = tb && tb.uids.includes(uid) && (tb.stage === "vote" || tb.stage === "playing");
    if (members.length > 0 && (room.status === "tiebreakVote" || round?.tiebreak) && tiedLeaver) {
      // A tied player left: no tie-breaker, the shared titles stand.
      next.status = "finished";
      next.tiebreak = { ...tb!, stage: "cancelled" };
    } else if (kqEffects) {
      kqEffects.apply();
      Object.assign(next, kqEffects.out);
    } else if (room.status === "playing" && members.length > 0 && members.length < MIN_PLAYERS) {
      // Too few players to continue: finish with the scores so far.
      const leftRoom = {
        ...room,
        players: { ...room.players, [uid]: { ...room.players[uid], left: true } },
      };
      next.status = "finished";
      next.final = standingsFor(leftRoom);
    }
    tx.update(ref, next);
    tx.create(auditRef(db, roomId), { type: "leave", uid, at: ts, roundKey: round?.roundKey ?? null });
  });
  return { ok: true };
}

// ---------- rounds ----------

/** Throws a clear error if the room can't play King & Queen with its players. */
function kqChainCheck(room: RoomDoc) {
  kqChain(room.kqSettings?.roles ?? KQ_DEFAULT_ROLES, room.memberUids.length);
}

/**
 * Deals a fresh round inside a transaction. Caller has already read `room`.
 * A tie-breaker round is dealt only to the tied players.
 */
function startRoundTx(
  tx: Transaction,
  deps: Deps,
  roomId: string,
  room: RoomDoc,
  opts: { players?: string[]; tiebreak?: boolean } = {},
) {
  const { db, now, rng } = deps;
  const players = opts.players ?? room.memberUids;
  const roundNo = room.currentRound + 1;
  const key = roundKeyFor(room.gameNo, roundNo);
  const pool = eligibleNames(room.settings.category, room.settings.difficulty, room.settings.customNames);
  const names = pickNames(pool, players.length, room.usedNames, rng);
  const deck = buildDeck(names, rng);
  const hands = dealHands(deck, players.length, rng);
  const order = shuffle(players, rng);
  const t = now();
  const ts = Timestamp.fromMillis(t);
  const timed = room.settings.turnSeconds > 0;
  const turnSeconds = timed ? room.settings.turnSeconds : RELAXED_TURN_SECONDS;
  const pickOpensAt = t + CHIT_CEREMONY_SECONDS * 1000;
  const pickDeadline = pickOpensAt + PICK_SECONDS * 1000;
  // Passing timestamps are set for real when the last chit is picked.
  const introEndsAt = pickDeadline + INTRO_SECONDS * 1000;

  // Hands start empty: each player fills theirs by picking folded chits.
  // Their fairly dealt slips wait in the server-only secrets document,
  // in a random order, and are handed out one per picked chit.
  const handSizes: Record<string, number> = {};
  const deal: Record<string, Card[]> = {};
  order.forEach((uid, i) => {
    handSizes[uid] = 0;
    deal[uid] = shuffle(hands[i], rng);
    tx.set(handRef(db, roomId, uid), {
      roundKey: key,
      cards: [],
      incomingCardId: null,
      character: null,
      updatedAt: ts,
    });
  });
  const chits = Array.from({ length: deck.length }, () => `m${randomId(rng, 12)}`);
  tx.set(secretRef(db, roomId, key), { deal, bound: {}, characters: {} });

  const round: RoundDoc = {
    roundKey: key,
    gameNo: room.gameNo,
    roundNo,
    tiebreak: opts.tiebreak === true,
    status: "picking",
    order,
    turnIndex: 0,
    turnId: 0,
    currentUid: order[0],
    nextUid: order[1 % order.length],
    timed,
    turnSeconds,
    chits,
    picks: {},
    pickOpensAt: Timestamp.fromMillis(pickOpensAt),
    pickDeadline: Timestamp.fromMillis(pickDeadline),
    introEndsAt: Timestamp.fromMillis(introEndsAt),
    turnDeadline: Timestamp.fromMillis(introEndsAt + turnSeconds * 1000),
    movieNames: names,
    handSizes,
    lastAction: null,
    timeouts: {},
    winner: null,
    charChits: [],
    charPicks: {},
    charPickOpensAt: null,
    charPickDeadline: null,
    revealAt: null,
    revealedHands: null,
    characters: null,
    scores: null,
    abortedReason: null,
    startedAt: ts,
    endedAt: null,
  };
  tx.set(roundRef(db, roomId, key), round);
  tx.update(roomRef(db, roomId), {
    status: "playing",
    currentRound: roundNo,
    currentRoundKey: key,
    usedNames: [...room.usedNames, ...names].slice(-300),
    updatedAt: ts,
  });
  tx.create(auditRef(db, roomId), {
    type: "deal",
    roundKey: key,
    order,
    hands: Object.fromEntries(order.map((uid, i) => [uid, hands[i]])),
    at: ts,
  });
  return key;
}

export async function startGame(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const roundKey = await deps.db.runTransaction(async (tx) => {
    const { room } = await loadRoom(tx, deps.db, roomId);
    requireHost(room, uid);
    if (room.status !== "lobby") fail("failed-precondition", "The game has already started.");
    const notReady = room.memberUids.filter((m) => m !== room.hostUid && !room.players[m].ready);
    if (notReady.length) {
      fail("failed-precondition", `Waiting for ${notReady.map((m) => room.players[m].name).join(", ")}.`);
    }
    const zero = Object.fromEntries(room.memberUids.map((m) => [m, 0]));
    const reset = { totals: zero, movieWins: zero, kingWins: { ...zero }, final: null, tiebreak: null, tiebreakScores: null };
    const fresh: RoomDoc = { ...room, ...reset, movieWins: { ...zero }, currentRound: 0 };
    if (room.mode === "kingQueen") {
      kqChainCheck(room);
      tx.update(roomRef(deps.db, roomId), reset);
      return kq.startKqRoundTx(tx, deps, roomId, fresh);
    }
    validateForStart(room.settings, room.memberUids.length);
    tx.update(roomRef(deps.db, roomId), reset);
    return startRoundTx(tx, deps, roomId, fresh);
  });
  return { roundKey };
}

export async function nextRound(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const roundKey = await deps.db.runTransaction(async (tx) => {
    const { room } = await loadRoom(tx, deps.db, roomId);
    requireHost(room, uid);
    if (room.status !== "playing") fail("failed-precondition", "The game is not in progress.");
    if (room.mode === "kingQueen") {
      const cur = await kq.kqCurrentRound(tx, deps.db, roomId, room.currentRoundKey);
      if (cur && cur.status !== "revealed" && cur.status !== "aborted") {
        fail("failed-precondition", "The current round has not finished.");
      }
      if (room.currentRound >= (room.kqSettings?.rounds ?? 7)) fail("failed-precondition", "All rounds are complete.");
      kqChainCheck(room);
      return kq.startKqRoundTx(tx, deps, roomId, room);
    }
    const current = room.currentRoundKey
      ? ((await tx.get(roundRef(deps.db, roomId, room.currentRoundKey))).data() as RoundDoc)
      : null;
    if (current && current.status !== "revealed" && current.status !== "aborted") {
      fail("failed-precondition", "The current round has not finished.");
    }
    if (room.currentRound >= room.settings.rounds) fail("failed-precondition", "All rounds are complete.");
    validateForStart(room.settings, room.memberUids.length);
    return startRoundTx(tx, deps, roomId, room);
  });
  return { roundKey };
}

/**
 * Shared pass path for player passes and server timeouts. Runs entirely in one
 * transaction so concurrent requests serialise and only one can match turnId.
 */
async function passTx(
  deps: Deps,
  roomId: string,
  roundKey: string,
  turnId: number,
  actor: { kind: "player"; uid: string; cardId: string; requestId: string } | { kind: "timeout"; uid: string },
) {
  const { db, now, rng } = deps;
  return db.runTransaction(async (tx) => {
    const { ref: rRef, room } = await loadRoom(tx, db, roomId);
    requireMember(room, actor.uid);
    if (room.currentRoundKey !== roundKey) fail("failed-precondition", "That round is over.");
    const roundSnap = await tx.get(roundRef(db, roomId, roundKey));
    const round = roundSnap.data() as RoundDoc;

    // Idempotent retry: the same request already moved this card.
    if (
      actor.kind === "player" &&
      round.lastAction?.requestId === actor.requestId &&
      round.lastAction.fromUid === actor.uid
    ) {
      return { duplicate: true, winner: round.winner?.uid ?? null };
    }
    if (round.status !== "exchange") fail("failed-precondition", "Passing has stopped for this round.");
    if (round.turnId !== turnId) fail("failed-precondition", "That turn has already finished.");

    const t = now();
    const deadline = round.turnDeadline.toMillis();
    if (t < round.introEndsAt.toMillis()) fail("failed-precondition", "The round has not started yet.");
    if (actor.kind === "player") {
      // A late player can still make their own move: nothing is auto-played.
      if (round.currentUid !== actor.uid) fail("permission-denied", "It is not your turn.");
    } else {
      await requirePlayFor(tx, db, roomId, [round.currentUid], deadline, t);
    }

    const fromUid = round.currentUid;
    const toUid = round.nextUid;
    const [fromSnap, toSnap] = await Promise.all([
      tx.get(handRef(db, roomId, fromUid)),
      tx.get(handRef(db, roomId, toUid)),
    ]);
    const fromHand = fromSnap.data() as HandDoc;
    const toHand = toSnap.data() as HandDoc;
    if (fromHand?.roundKey !== roundKey || toHand?.roundKey !== roundKey) {
      fail("failed-precondition", "Hands are out of sync with this round.");
    }

    const cardId =
      actor.kind === "player"
        ? actor.cardId
        : timeoutCard(fromHand.cards, fromHand.incomingCardId, room.settings.timeoutPolicy, rng).id;

    const state: ExchangeState = {
      order: round.order,
      turnIndex: round.turnIndex,
      turnId: round.turnId,
      hands: { [fromUid]: fromHand.cards, [toUid]: toHand.cards },
      incoming: { [fromUid]: fromHand.incomingCardId, [toUid]: toHand.incomingCardId },
    };
    const result = applyPass(state, fromUid, cardId, turnId);
    const ts = Timestamp.fromMillis(t);
    const s = result.state;
    const nextIndex = s.turnIndex;
    const lastAction: LastAction = {
      type: actor.kind === "player" ? "pass" : "timeout",
      fromUid,
      toUid,
      turnId,
      requestId: actor.kind === "player" ? actor.requestId : null,
      at: ts,
    };

    tx.update(handRef(db, roomId, fromUid), { cards: s.hands[fromUid], incomingCardId: null, updatedAt: ts });
    tx.update(handRef(db, roomId, toUid), { cards: s.hands[toUid], incomingCardId: result.card.id, updatedAt: ts });

    const roundUpdate: Record<string, unknown> = {
      turnIndex: nextIndex,
      turnId: s.turnId,
      currentUid: s.order[nextIndex],
      nextUid: s.order[(nextIndex + 1) % s.order.length],
      turnDeadline: Timestamp.fromMillis(t + round.turnSeconds * 1000),
      [`handSizes.${fromUid}`]: s.hands[fromUid].length,
      [`handSizes.${toUid}`]: s.hands[toUid].length,
      lastAction,
    };
    if (actor.kind === "timeout") roundUpdate[`timeouts.${fromUid}`] = (round.timeouts[fromUid] ?? 0) + 1;

    if (result.winner) {
      const w = result.winner;
      // Seal one character into each folded chit; non-winners pick them.
      const others = round.order.filter((u) => u !== w.uid);
      const defs = shuffle(charactersFor(room.settings.characters, others.length), rng);
      const sealed: Record<string, { name: string; points: number }> = {};
      for (const def of defs) sealed[`c${randomId(rng, 12)}`] = { name: def.name, points: def.points };
      const charChits = shuffle(Object.keys(sealed), rng);
      const opens = t + CHAR_CEREMONY_SECONDS * 1000;
      tx.update(secretRef(db, roomId, roundKey), { characters: sealed });
      Object.assign(roundUpdate, {
        status: "characters",
        winner: { uid: w.uid, movie: w.name, points: room.settings.winPoints, at: ts },
        charChits,
        charPicks: {},
        charPickOpensAt: Timestamp.fromMillis(opens),
        charPickDeadline: Timestamp.fromMillis(opens + CHAR_PICK_SECONDS * 1000),
        revealAt: null,
      });
      // Movie-win points are applied exactly once, guarded by the status change.
      // Tie-breaker points only order the tied players, so totals stay as they were.
      if (!round.tiebreak) {
        tx.update(rRef, {
          [`totals.${w.uid}`]: (room.totals[w.uid] ?? 0) + room.settings.winPoints,
          [`movieWins.${w.uid}`]: (room.movieWins[w.uid] ?? 0) + 1,
          updatedAt: ts,
        });
      }
      tx.create(auditRef(db, roomId), { type: "characterChits", roundKey, sealed, at: ts });
    }
    tx.update(roundRef(db, roomId, roundKey), roundUpdate);
    tx.create(auditRef(db, roomId), {
      type: lastAction.type,
      roundKey,
      turnId,
      fromUid,
      toUid,
      card: result.card,
      requestId: lastAction.requestId,
      winner: result.winner,
      at: ts,
    });
    return { duplicate: false, winner: result.winner?.uid ?? null };
  });
}

// ---------- picking folded chits ----------

/** The slip each movie chit revealed, plus whether passing can start. */
function bindMovieChits(
  tx: Transaction,
  deps: Deps,
  roomId: string,
  round: RoundDoc,
  secret: SecretDoc,
  hands: Record<string, HandDoc>,
  assignments: [chitId: string, uid: string][],
  t: number,
  auto: boolean,
) {
  const { db } = deps;
  const ts = Timestamp.fromMillis(t);
  const deal = { ...secret.deal };
  const bound = { ...secret.bound };
  const picks = { ...round.picks };
  const cards: Record<string, Card[]> = {};
  const revealed: Record<string, Card> = {};
  for (const [chitId, uid] of assignments) {
    const remaining = deal[uid] ?? [];
    if (remaining.length === 0) fail("failed-precondition", "You already have 4 chits.");
    const [card, ...rest] = remaining;
    deal[uid] = rest;
    bound[chitId] = card.id;
    picks[chitId] = uid;
    cards[uid] = [...(cards[uid] ?? hands[uid].cards), card];
    revealed[chitId] = card;
  }
  for (const [uid, list] of Object.entries(cards)) {
    tx.update(handRef(db, roomId, uid), { cards: list, updatedAt: ts });
  }
  tx.update(secretRef(db, roomId, round.roundKey), { deal, bound });

  const update: Record<string, unknown> = { picks };
  for (const uid of Object.keys(cards)) update[`handSizes.${uid}`] = cards[uid].length;
  const complete = Object.keys(picks).length === round.chits.length;
  if (complete) {
    // Everyone holds 4 slips: show the circle, then passing begins.
    const intro = t + INTRO_SECONDS * 1000;
    Object.assign(update, {
      status: "exchange",
      introEndsAt: Timestamp.fromMillis(intro),
      turnDeadline: Timestamp.fromMillis(intro + round.turnSeconds * 1000),
    });
  }
  tx.update(roundRef(db, roomId, round.roundKey), update);
  tx.create(auditRef(db, roomId), {
    type: auto ? "autoPick" : "pick",
    roundKey: round.roundKey,
    picks: Object.fromEntries(assignments),
    cards: revealed,
    at: ts,
  });
  return { revealed, complete };
}

async function loadPicking(tx: Transaction, deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const roundKey = str(data, "roundKey");
  const { room } = await loadRoom(tx, deps.db, roomId);
  requireMember(room, uid);
  if (room.currentRoundKey !== roundKey) fail("failed-precondition", "That round is over.");
  const [roundSnap, secretSnap] = await Promise.all([
    tx.get(roundRef(deps.db, roomId, roundKey)),
    tx.get(secretRef(deps.db, roomId, roundKey)),
  ]);
  const round = roundSnap.data() as RoundDoc;
  const secret = secretSnap.data() as SecretDoc;
  if (!round || !secret) fail("not-found", "Round not found.");
  return { roomId, roundKey, room, round, secret };
}

/** A player picks one folded movie chit from the table. */
export async function pickChit(deps: Deps, uid: string, data: unknown) {
  const chitId = str(data, "chitId");
  return deps.db.runTransaction(async (tx) => {
    const { roomId, round, secret } = await loadPicking(tx, deps, uid, data);
    if (!round.order.includes(uid)) fail("permission-denied", "You are not playing this round.");
    const handSnap = await tx.get(handRef(deps.db, roomId, uid));
    const hand = handSnap.data() as HandDoc;
    if (round.picks[chitId] === uid) {
      // Retried request: return the same slip, change nothing.
      const card = hand.cards.find((c) => c.id === secret.bound[chitId]);
      return { duplicate: true, card };
    }
    if (round.status !== "picking") fail("failed-precondition", "Picking has finished.");
    const t = deps.now();
    if (t < round.pickOpensAt.toMillis()) fail("failed-precondition", "The chits are still being shuffled.");
    if (!round.chits.includes(chitId)) fail("invalid-argument", "That chit is not on the table.");
    if (round.picks[chitId]) fail("already-exists", "Someone else picked that chit first.");
    if (hand.cards.length >= HAND_SIZE) fail("failed-precondition", "You already have 4 chits.");
    const { revealed } = bindMovieChits(tx, deps, roomId, round, secret, { [uid]: hand }, [[chitId, uid]], t, false);
    return { duplicate: false, card: revealed[chitId] };
  });
}

/** Picks at random for players still picking, once [requirePlayFor] allows it. */
export async function autoPickChits(deps: Deps, uid: string, data: unknown) {
  return deps.db.runTransaction(async (tx) => {
    const { roomId, round, secret } = await loadPicking(tx, deps, uid, data);
    if (round.status !== "picking") return { assigned: 0 };
    const t = deps.now();
    const snaps = await Promise.all(round.order.map((u) => tx.get(handRef(deps.db, roomId, u))));
    const hands: Record<string, HandDoc> = {};
    round.order.forEach((u, i) => (hands[u] = snaps[i].data() as HandDoc));
    const late = round.order.filter((u) => hands[u].cards.length < HAND_SIZE);
    await requirePlayFor(tx, deps.db, roomId, late, round.pickDeadline.toMillis(), t);
    const free = shuffle(round.chits.filter((c) => !round.picks[c]), deps.rng);
    const assignments: [string, string][] = [];
    for (const u of round.order) {
      for (let n = hands[u].cards.length; n < HAND_SIZE; n++) assignments.push([free.pop()!, u]);
    }
    bindMovieChits(tx, deps, roomId, round, secret, hands, assignments, t, true);
    return { assigned: assignments.length };
  });
}

function bindCharacterChits(
  tx: Transaction,
  deps: Deps,
  roomId: string,
  round: RoundDoc,
  secret: SecretDoc,
  assignments: [chitId: string, uid: string][],
  t: number,
  auto: boolean,
) {
  const ts = Timestamp.fromMillis(t);
  const charPicks = { ...round.charPicks };
  for (const [chitId, uid] of assignments) {
    charPicks[chitId] = uid;
    tx.update(handRef(deps.db, roomId, uid), { character: secret.characters[chitId], updatedAt: ts });
  }
  const update: Record<string, unknown> = { charPicks };
  const complete = Object.keys(charPicks).length === round.charChits.length;
  // Everyone peeks at their own character privately before the public reveal.
  if (complete) update.revealAt = Timestamp.fromMillis(t + REVEAL_DELAY_SECONDS * 1000);
  tx.update(roundRef(deps.db, roomId, round.roundKey), update);
  tx.create(auditRef(deps.db, roomId), {
    type: auto ? "autoPickCharacter" : "pickCharacter",
    roundKey: round.roundKey,
    picks: Object.fromEntries(assignments),
    at: ts,
  });
}

/** A non-winner picks one folded character chit and privately sees it. */
export async function pickCharacter(deps: Deps, uid: string, data: unknown) {
  const chitId = str(data, "chitId");
  return deps.db.runTransaction(async (tx) => {
    const { roomId, round, secret } = await loadPicking(tx, deps, uid, data);
    if (round.charPicks?.[chitId] === uid) {
      return { duplicate: true, character: secret.characters[chitId] };
    }
    if (round.status !== "characters" || round.revealAt) {
      fail("failed-precondition", "Character picking has finished.");
    }
    if (!round.order.includes(uid) || round.winner?.uid === uid) {
      fail("permission-denied", "Only players who did not win pick a character.");
    }
    const t = deps.now();
    if (t < round.charPickOpensAt!.toMillis()) fail("failed-precondition", "The character chits are still being folded.");
    if (!round.charChits.includes(chitId)) fail("invalid-argument", "That chit is not on the table.");
    if (round.charPicks[chitId]) fail("already-exists", "Someone else picked that chit first.");
    if (Object.values(round.charPicks).includes(uid)) fail("failed-precondition", "You already picked a character.");
    bindCharacterChits(tx, deps, roomId, round, secret, [[chitId, uid]], t, false);
    return { duplicate: false, character: secret.characters[chitId] };
  });
}

/** Picks characters at random for late players, once [requirePlayFor] allows it. */
export async function autoPickCharacters(deps: Deps, uid: string, data: unknown) {
  return deps.db.runTransaction(async (tx) => {
    const { roomId, round, secret } = await loadPicking(tx, deps, uid, data);
    if (round.status !== "characters" || round.revealAt) return { assigned: 0 };
    const t = deps.now();
    const picked = new Set(Object.values(round.charPicks));
    const waiting = round.order.filter((u) => u !== round.winner!.uid && !picked.has(u));
    await requirePlayFor(tx, deps.db, roomId, waiting, round.charPickDeadline!.toMillis(), t);
    const free = shuffle(round.charChits.filter((c) => !round.charPicks[c]), deps.rng);
    const assignments = waiting.map((u) => [free.pop()!, u] as [string, string]);
    bindCharacterChits(tx, deps, roomId, round, secret, assignments, t, true);
    return { assigned: assignments.length };
  });
}

export async function passCard(deps: Deps, uid: string, data: unknown) {
  return passTx(deps, str(data, "roomId"), str(data, "roundKey"), int(data, "turnId"), {
    kind: "player",
    uid,
    cardId: str(data, "cardId"),
    requestId: str(data, "requestId"),
  });
}

/** Another member plays a late player's turn, once [requirePlayFor] allows it. */
export async function claimTimeout(deps: Deps, uid: string, data: unknown) {
  return passTx(deps, str(data, "roomId"), str(data, "roundKey"), int(data, "turnId"), {
    kind: "timeout",
    uid,
  });
}

export async function revealRound(deps: Deps, uid: string, data: unknown) {
  const { db, now } = deps;
  const roomId = str(data, "roomId");
  const roundKey = str(data, "roundKey");
  return db.runTransaction(async (tx) => {
    const { ref, room } = await loadRoom(tx, db, roomId);
    requireMember(room, uid);
    const rRef = roundRef(db, roomId, roundKey);
    const round = (await tx.get(rRef)).data() as RoundDoc | undefined;
    if (!round) fail("not-found", "Round not found.");
    if (round!.status === "revealed") return { alreadyRevealed: true };
    if (round!.status !== "characters" || !round!.winner) fail("failed-precondition", "Nothing to reveal yet.");
    const t = now();
    if (!round!.revealAt) fail("failed-precondition", "Players are still picking their characters.");
    if (t < round!.revealAt!.toMillis() && uid !== room.hostUid) {
      fail("failed-precondition", "The reveal has not started yet.");
    }
    const handSnaps = await Promise.all(round!.order.map((u) => tx.get(handRef(db, roomId, u))));
    const revealedHands: Record<string, Card[]> = {};
    const characters: Record<string, { name: string; points: number }> = {};
    round!.order.forEach((u, i) => {
      const h = handSnaps[i].data() as HandDoc;
      revealedHands[u] = h.cards;
      if (h.character) characters[u] = h.character;
    });
    const scores = roundScores(round!.order, round!.winner!.uid, round!.winner!.points, characters);
    const ts = Timestamp.fromMillis(t);

    let roomUpdate: Record<string, unknown>;
    if (round!.tiebreak) {
      // The tie-breaker orders the tied players; totals are untouched.
      const tiebreakScores = scores;
      roomUpdate = {
        status: "finished",
        tiebreakScores,
        final: standingsFor({ ...room, tiebreakScores }),
        tiebreak: room.tiebreak ? { ...room.tiebreak, stage: "done" } : null,
        updatedAt: ts,
      };
    } else {
      const totals = { ...room.totals };
      for (const [u, c] of Object.entries(characters)) totals[u] = (totals[u] ?? 0) + c.points;
      roomUpdate = { totals, updatedAt: ts };
      if (room.status === "finished") {
        roomUpdate.final = standingsFor({ ...room, totals });
      } else if (room.currentRound >= room.settings.rounds) {
        Object.assign(roomUpdate, endOfGameUpdate({ ...room, totals }, t));
      }
    }
    tx.update(rRef, { status: "revealed", revealedHands, characters, scores, endedAt: ts });
    tx.update(ref, roomUpdate);
    return { alreadyRevealed: false };
  });
}

export async function playAgain(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  await deps.db.runTransaction(async (tx) => {
    const { ref, room } = await loadRoom(tx, deps.db, roomId);
    requireHost(room, uid);
    if (room.status !== "finished") fail("failed-precondition", "The game has not finished.");
    const players: RoomDoc["players"] = {};
    for (const m of room.memberUids) players[m] = { ...room.players[m], ready: m === room.hostUid, left: false };
    tx.update(ref, {
      status: "lobby",
      players,
      gameNo: room.gameNo + 1,
      currentRound: 0,
      currentRoundKey: null,
      totals: {},
      movieWins: {},
      kingWins: {},
      final: null,
      tiebreak: null,
      tiebreakScores: null,
      updatedAt: Timestamp.fromMillis(deps.now()),
    });
  });
  return { ok: true };
}

// ---------- tie-breaker ----------

function declineTiebreak(tx: Transaction, deps: Deps, roomId: string, tb: TiebreakState, votes: Record<string, boolean>) {
  tx.update(roomRef(deps.db, roomId), {
    status: "finished",
    tiebreak: { ...tb, votes, stage: "declined" },
    updatedAt: Timestamp.fromMillis(deps.now()),
  });
}

/**
 * A tied player accepts or rejects the tie-breaker. Any rejection keeps the
 * shared titles; when every tied player accepts, the round starts at once.
 */
export async function tiebreakVote(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const accept = (data as Record<string, unknown>).accept === true;
  return deps.db.runTransaction(async (tx) => {
    const { room } = await loadRoom(tx, deps.db, roomId);
    requireMember(room, uid);
    const tb = room.tiebreak;
    if (room.status !== "tiebreakVote" || !tb || tb.stage !== "vote") {
      fail("failed-precondition", "There is no tie-breaker vote open.");
    }
    if (!tb!.uids.includes(uid)) fail("permission-denied", "Only the tied players decide on a tie-breaker.");
    if (deps.now() > tb!.deadline.toMillis()) fail("failed-precondition", "The vote has closed.");
    const votes = { ...tb!.votes, [uid]: accept };
    if (!accept) {
      declineTiebreak(tx, deps, roomId, tb!, votes);
      return { outcome: "declined" };
    }
    if (tb!.uids.every((u) => votes[u] === true)) {
      const roundKey = startRoundTx(tx, deps, roomId, room, { players: tb!.uids, tiebreak: true });
      tx.update(roomRef(deps.db, roomId), { tiebreak: { ...tb!, votes, stage: "playing" } });
      return { outcome: "started", roundKey };
    }
    tx.update(roomRef(deps.db, roomId), {
      [`tiebreak.votes.${uid}`]: true,
      updatedAt: Timestamp.fromMillis(deps.now()),
    });
    return { outcome: "waiting" };
  });
}

/** After the vote deadline, any member may close it: silence counts as no. */
export async function resolveTiebreakVote(deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  return deps.db.runTransaction(async (tx) => {
    const { room } = await loadRoom(tx, deps.db, roomId);
    requireMember(room, uid);
    const tb = room.tiebreak;
    if (room.status !== "tiebreakVote" || !tb || tb.stage !== "vote") return { outcome: "none" };
    if (deps.now() <= tb.deadline.toMillis()) fail("failed-precondition", "The vote is still open.");
    declineTiebreak(tx, deps, roomId, tb, tb.votes);
    return { outcome: "declined" };
  });
}

/**
 * Closes rooms nobody has touched for a while and frees their codes, then
 * permanently deletes rooms (with hands, rounds, presence and audit logs)
 * that have been closed for longer than `deleteAfterMs`.
 */
export async function expireRooms(deps: Deps, olderThanMs: number, deleteAfterMs = 7 * 24 * 3600 * 1000) {
  const { db, now } = deps;
  const cutoff = Timestamp.fromMillis(now() - olderThanMs);
  const stale = await db.collection("rooms").where("updatedAt", "<", cutoff).limit(200).get();
  let closed = 0;
  let deleted = 0;
  for (const doc of stale.docs) {
    const room = doc.data() as RoomDoc;
    if (room.status === "closed") {
      if (room.updatedAt.toMillis() < now() - deleteAfterMs) {
        await db.recursiveDelete(doc.ref);
        deleted++;
      }
      continue;
    }
    const batch = db.batch();
    batch.update(doc.ref, { status: "closed", updatedAt: Timestamp.fromMillis(now()) });
    batch.delete(db.collection("roomCodes").doc(room.code));
    await batch.commit();
    closed++;
  }
  return { closed, deleted };
}
