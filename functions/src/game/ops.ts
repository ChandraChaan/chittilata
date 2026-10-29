import {
  DocumentReference,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {
  applyPass,
  assignCharacters,
  buildDeck,
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
  rankPlayers,
  RELAXED_TURN_SECONDS,
  Rng,
  roomCode,
  roundScores,
  shuffle,
  timeoutCard,
  validateForStart,
} from "../engine";
import {
  DEADLINE_GRACE_MS,
  HandDoc,
  INTRO_SECONDS,
  LastAction,
  REVEAL_DELAY_SECONDS,
  RoomDoc,
  roundKeyFor,
  RoundDoc,
} from "./model";

export interface Deps {
  db: Firestore;
  now: () => number;
  rng: Rng;
}

const fail = (code: GameError["code"], msg: string): never => {
  throw new GameError(code, msg);
};

// ---------- helpers ----------

const roomRef = (db: Firestore, roomId: string) =>
  db.collection("rooms").doc(roomId) as DocumentReference<RoomDoc>;
const roundRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("rounds").doc(key) as DocumentReference<RoundDoc>;
const handRef = (db: Firestore, roomId: string, uid: string) =>
  db.collection("rooms").doc(roomId).collection("hands").doc(uid) as DocumentReference<HandDoc>;
const auditRef = (db: Firestore, roomId: string) =>
  db.collection("rooms").doc(roomId).collection("audit").doc();

function str(data: unknown, field: string, max = 64): string {
  const v = (data as Record<string, unknown> | null)?.[field];
  if (typeof v !== "string" || !v || v.length > max) fail("invalid-argument", `Missing ${field}.`);
  return v as string;
}

function int(data: unknown, field: string): number {
  const v = (data as Record<string, unknown> | null)?.[field];
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0) fail("invalid-argument", `Missing ${field}.`);
  return v as number;
}

async function loadRoom(tx: Transaction, db: Firestore, roomId: string) {
  const ref = roomRef(db, roomId);
  const snap = await tx.get(ref);
  if (!snap.exists) fail("not-found", "This room no longer exists.");
  const room = snap.data() as RoomDoc;
  if (room.status === "closed") fail("not-found", "This room has closed.");
  return { ref, room };
}

function requireMember(room: RoomDoc, uid: string) {
  if (!room.memberUids.includes(uid)) fail("permission-denied", "You are not in this room.");
}

function requireHost(room: RoomDoc, uid: string) {
  requireMember(room, uid);
  if (room.hostUid !== uid) fail("permission-denied", "Only the host can do that.");
}

/** Host passes to the longest-standing remaining member. */
function migrateHost(room: RoomDoc): string {
  return room.memberUids.includes(room.hostUid) ? room.hostUid : (room.memberUids[0] ?? room.hostUid);
}

function standingsFor(room: RoomDoc) {
  return rankPlayers(
    Object.entries(room.players).map(([uid, p]) => ({
      uid,
      name: p.name,
      total: room.totals[uid] ?? 0,
      movieWins: room.movieWins[uid] ?? 0,
      left: p.left,
    })),
  );
}

// ---------- lobby ----------

export async function createRoom(deps: Deps, uid: string, data: unknown) {
  const name = cleanPlayerName((data as Record<string, unknown> | null)?.name);
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
        settings: defaultSettings(),
        gameNo: 1,
        currentRound: 0,
        currentRoundKey: null,
        totals: {},
        movieWins: {},
        usedNames: [],
        final: null,
        createdAt: ts,
        updatedAt: ts,
      };
      tx.create(ref, room);
      tx.create(codeRef, { roomId: ref.id, createdAt: ts });
      return true;
    });
    if (created) return { roomId: ref.id, code };
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
    const round =
      room.status === "playing" && room.currentRoundKey
        ? ((await tx.get(roundRef(db, roomId, room.currentRoundKey))).data() as RoundDoc | undefined)
        : undefined;

    const ts = Timestamp.fromMillis(now());
    const members = room.memberUids.filter((m) => m !== uid);
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

    if (round && round.status === "exchange" && members.length > 0) {
      // The leaver's cards cannot keep circulating, so the round is void.
      tx.update(roundRef(db, roomId, round.roundKey), {
        status: "aborted",
        abortedReason: `${room.players[uid].name} left the game.`,
        endedAt: ts,
      });
    }
    if (room.status === "playing" && members.length > 0 && members.length < MIN_PLAYERS) {
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

/** Deals a fresh round inside a transaction. Caller has already read `room`. */
function startRoundTx(tx: Transaction, deps: Deps, roomId: string, room: RoomDoc) {
  const { db, now, rng } = deps;
  const players = room.memberUids;
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
  const introEndsAt = t + INTRO_SECONDS * 1000;

  const handSizes: Record<string, number> = {};
  order.forEach((uid, i) => {
    handSizes[uid] = HAND_SIZE;
    tx.set(handRef(db, roomId, uid), {
      roundKey: key,
      cards: hands[i],
      incomingCardId: null,
      character: null,
      updatedAt: ts,
    });
  });

  const round: RoundDoc = {
    roundKey: key,
    gameNo: room.gameNo,
    roundNo,
    status: "exchange",
    order,
    turnIndex: 0,
    turnId: 0,
    currentUid: order[0],
    nextUid: order[1 % order.length],
    timed,
    turnSeconds,
    introEndsAt: Timestamp.fromMillis(introEndsAt),
    turnDeadline: Timestamp.fromMillis(introEndsAt + turnSeconds * 1000),
    movieNames: names,
    handSizes,
    lastAction: null,
    timeouts: {},
    winner: null,
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
    validateForStart(room.settings, room.memberUids.length);
    const zero = Object.fromEntries(room.memberUids.map((m) => [m, 0]));
    const fresh: RoomDoc = { ...room, totals: zero, movieWins: { ...zero }, currentRound: 0 };
    tx.update(roomRef(deps.db, roomId), { totals: zero, movieWins: zero, final: null });
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
      if (round.currentUid !== actor.uid) fail("permission-denied", "It is not your turn.");
      if (t > deadline + DEADLINE_GRACE_MS) fail("failed-precondition", "Time is up for this turn.");
    } else if (t <= deadline + DEADLINE_GRACE_MS) {
      fail("failed-precondition", "The turn has not timed out yet.");
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
      const others = round.order.filter((u) => u !== w.uid);
      const chars = assignCharacters(others, room.settings.characters, rng);
      for (const u of others) tx.update(handRef(db, roomId, u), { character: chars[u] });
      Object.assign(roundUpdate, {
        status: "characters",
        winner: { uid: w.uid, movie: w.name, points: room.settings.winPoints, at: ts },
        revealAt: Timestamp.fromMillis(t + REVEAL_DELAY_SECONDS * 1000),
      });
      // Movie-win points are applied exactly once, guarded by the status change.
      tx.update(rRef, {
        [`totals.${w.uid}`]: (room.totals[w.uid] ?? 0) + room.settings.winPoints,
        [`movieWins.${w.uid}`]: (room.movieWins[w.uid] ?? 0) + 1,
        updatedAt: ts,
      });
      tx.create(auditRef(db, roomId), { type: "characters", roundKey, characters: chars, at: ts });
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

export async function passCard(deps: Deps, uid: string, data: unknown) {
  return passTx(deps, str(data, "roomId"), str(data, "roundKey"), int(data, "turnId"), {
    kind: "player",
    uid,
    cardId: str(data, "cardId"),
    requestId: str(data, "requestId"),
  });
}

/** Any member may ask the server to apply an expired turn's timeout. */
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

    const totals = { ...room.totals };
    for (const [u, c] of Object.entries(characters)) totals[u] = (totals[u] ?? 0) + c.points;
    const roomUpdate: Record<string, unknown> = { totals, updatedAt: ts };
    if (room.currentRound >= room.settings.rounds || room.status === "finished") {
      roomUpdate.status = "finished";
      roomUpdate.final = standingsFor({ ...room, totals });
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
      final: null,
      updatedAt: Timestamp.fromMillis(deps.now()),
    });
  });
  return { ok: true };
}

/** Closes rooms nobody has touched for a while and frees their codes. */
export async function expireRooms(deps: Deps, olderThanMs: number) {
  const { db, now } = deps;
  const cutoff = Timestamp.fromMillis(now() - olderThanMs);
  const stale = await db.collection("rooms").where("updatedAt", "<", cutoff).limit(200).get();
  let closed = 0;
  for (const doc of stale.docs) {
    const room = doc.data() as RoomDoc;
    if (room.status === "closed") continue;
    const batch = db.batch();
    batch.update(doc.ref, { status: "closed", updatedAt: Timestamp.fromMillis(now()) });
    batch.delete(db.collection("roomCodes").doc(room.code));
    await batch.commit();
    closed++;
  }
  return closed;
}
