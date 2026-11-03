import { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { eligibleNames, pickNames, shuffle } from "../engine";
import type { Deps } from "./ops";
import { fail, int, isBot, loadRoom, requireMember, roomRef, standingsFor, str, warningAnswered } from "./ops";
import { DEADLINE_GRACE_MS, RoomDoc, roundKeyFor } from "./model";

/**
 * Movie Dumb Charades: each round one player (taking turns) secretly sees a
 * movie and acts it out without words; everyone else picks the title from
 * six choices on their phone. No free text anywhere.
 *
 *   rooms/{id}/charades/{key}  public round: actor, choices, guesses
 *   rooms/{id}/cards/{uid}     the actor's secret movie (owner only)
 *   rooms/{id}/secrets/{key}   the right choice (server only)
 */
export interface CharadesRoundDoc {
  roundKey: string;
  gameNo: number;
  roundNo: number;
  status: "acting" | "revealed";
  actor: string;
  options: string[];
  /** Acting starts after a short "get ready" so the actor can read the title. */
  startsAt: Timestamp;
  deadline: Timestamp;
  /** uid -> chosen option index (one guess each). */
  guesses: Record<string, number>;
  solvedBy: string | null;
  /** Revealed at the end. */
  answer: number | null;
  scores: Record<string, number> | null;
  endedReason: string | null;
  startedAt: Timestamp;
  endedAt: Timestamp | null;
}

export const CHARADES_OPTIONS = 6;
export const CHARADES_READY_SECONDS = 5;
export const CHARADES_SECONDS = 75;
export const CHARADES_MIN_PLAYERS = 3;
/** Points: the first right guess (more for a fast one) and the actor. */
export const GUESS_POINTS = 100;
export const SPEED_POINTS_PER_SECOND = 2;
export const ACTOR_POINTS = 75;

export const charadesRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("charades").doc(key);
const cardRef = (db: Firestore, roomId: string, uid: string) =>
  db.collection("rooms").doc(roomId).collection("cards").doc(uid);
const secretRef = (db: Firestore, roomId: string, key: string) =>
  db.collection("rooms").doc(roomId).collection("secrets").doc(key);

/** Who acts in round [roundNo]: people take turns (bots never act). */
export function actorFor(room: RoomDoc, roundNo: number): string {
  const people = room.memberUids.filter((u) => !isBot(u));
  return people[(roundNo - 1) % people.length];
}

export function startCharadesRoundTx(tx: Transaction, deps: Deps, roomId: string, room: RoomDoc) {
  const { db, now, rng } = deps;
  const people = room.memberUids.filter((u) => !isBot(u));
  if (people.length < CHARADES_MIN_PLAYERS) {
    fail("failed-precondition", `Dumb Charades needs at least ${CHARADES_MIN_PLAYERS} people.`);
  }
  const roundNo = room.currentRound + 1;
  const key = roundKeyFor(room.gameNo, roundNo);
  const pool = eligibleNames(room.settings.category, room.settings.difficulty, room.settings.customNames);
  const names = pickNames(pool, CHARADES_OPTIONS, room.usedNames, rng);
  const movie = names[0];
  const options = shuffle(names, rng);
  const t = now();
  const startsAt = t + CHARADES_READY_SECONDS * 1000;
  const actor = actorFor(room, roundNo);
  const round: CharadesRoundDoc = {
    roundKey: key,
    gameNo: room.gameNo,
    roundNo,
    status: "acting",
    actor,
    options,
    startsAt: Timestamp.fromMillis(startsAt),
    deadline: Timestamp.fromMillis(startsAt + CHARADES_SECONDS * 1000),
    guesses: {},
    solvedBy: null,
    answer: null,
    scores: null,
    endedReason: null,
    startedAt: Timestamp.fromMillis(t),
    endedAt: null,
  };
  tx.create(charadesRef(db, roomId, key), round);
  tx.set(secretRef(db, roomId, key), { answer: options.indexOf(movie) });
  tx.set(cardRef(db, roomId, actor), { roundKey: key, movie, updatedAt: Timestamp.fromMillis(t) });
  tx.update(roomRef(db, roomId), {
    status: "playing",
    currentRound: roundNo,
    currentRoundKey: key,
    usedNames: [...room.usedNames, movie].slice(-200),
    updatedAt: Timestamp.fromMillis(t),
  });
  return key;
}

/** Ends a round: scores, totals, and the game's end after the last round. */
function revealTx(
  tx: Transaction,
  deps: Deps,
  roomId: string,
  room: RoomDoc,
  round: CharadesRoundDoc,
  answer: number,
  solvedBy: string | null,
  reason: string | null,
) {
  const t = deps.now();
  const scores: Record<string, number> = {};
  if (solvedBy) {
    const left = Math.max(0, Math.ceil((round.deadline.toMillis() - t) / 1000));
    scores[solvedBy] = GUESS_POINTS + left * SPEED_POINTS_PER_SECOND;
    scores[round.actor] = ACTOR_POINTS;
  }
  const ts = Timestamp.fromMillis(t);
  tx.update(charadesRef(deps.db, roomId, round.roundKey), {
    status: "revealed",
    answer,
    solvedBy,
    scores,
    endedReason: reason,
    endedAt: ts,
  });
  const totals = { ...room.totals };
  const movieWins = { ...room.movieWins };
  for (const [u, p] of Object.entries(scores)) totals[u] = (totals[u] ?? 0) + p;
  // movieWins counts right guesses: the tie-break after points.
  if (solvedBy) movieWins[solvedBy] = (movieWins[solvedBy] ?? 0) + 1;
  const update: Record<string, unknown> = { totals, movieWins, updatedAt: ts };
  if (room.currentRound >= room.settings.rounds) {
    update.status = "finished";
    update.final = standingsFor({ ...room, totals, movieWins });
  }
  tx.update(roomRef(deps.db, roomId), update);
}

async function loadRound(tx: Transaction, deps: Deps, uid: string, data: unknown) {
  const roomId = str(data, "roomId");
  const roundKey = str(data, "roundKey");
  const { room } = await loadRoom(tx, deps.db, roomId);
  requireMember(room, uid);
  if (room.currentRoundKey !== roundKey) fail("failed-precondition", "That round is over.");
  const [rSnap, sSnap] = await Promise.all([
    tx.get(charadesRef(deps.db, roomId, roundKey)),
    tx.get(secretRef(deps.db, roomId, roundKey)),
  ]);
  const round = rSnap.data() as CharadesRoundDoc | undefined;
  if (!round) fail("not-found", "Round not found.");
  return { roomId, room, round: round!, answer: sSnap.data()?.answer as number };
}

/** A guesser picks one of the six titles. One guess per round each. */
export async function charadesGuess(deps: Deps, uid: string, data: unknown) {
  const option = int(data, "option");
  return deps.db.runTransaction(async (tx) => {
    const { roomId, room, round, answer } = await loadRound(tx, deps, uid, data);
    if (round.guesses[uid] !== undefined) return { correct: round.guesses[uid] === answer, duplicate: true };
    if (round.status !== "acting") fail("failed-precondition", "This round is over.");
    if (uid === round.actor) fail("permission-denied", "You're acting — no guessing!");
    if (option >= round.options.length) fail("invalid-argument", "Pick one of the titles.");
    const t = deps.now();
    if (t < round.startsAt.toMillis()) fail("failed-precondition", "Wait for the acting to start.");
    if (t > round.deadline.toMillis() + DEADLINE_GRACE_MS) fail("failed-precondition", "Time's up.");
    const guesses = { ...round.guesses, [uid]: option };
    const correct = option === answer;
    const guessers = room.memberUids.filter((u) => u !== round.actor);
    if (correct) {
      tx.update(charadesRef(deps.db, roomId, round.roundKey), { guesses });
      revealTx(tx, deps, roomId, room, { ...round, guesses }, answer, uid, null);
    } else if (guessers.every((u) => guesses[u] !== undefined || isBot(u))) {
      // Everyone guessed wrong: nobody can get it any more.
      tx.update(charadesRef(deps.db, roomId, round.roundKey), { guesses });
      revealTx(tx, deps, roomId, room, { ...round, guesses }, answer, null, "Nobody guessed it.");
    } else {
      tx.update(charadesRef(deps.db, roomId, round.roundKey), { guesses });
    }
    const answered = warningAnswered(room, uid);
    if (answered) tx.update(roomRef(deps.db, roomId), answered);
    return { correct, duplicate: false };
  });
}

/** After the timer, anyone in the room may end the round (nobody scores). */
export async function charadesReveal(deps: Deps, uid: string, data: unknown) {
  return deps.db.runTransaction(async (tx) => {
    const { roomId, room, round, answer } = await loadRound(tx, deps, uid, data);
    if (round.status !== "acting") return { revealed: false };
    if (deps.now() <= round.deadline.toMillis() + DEADLINE_GRACE_MS) fail("failed-precondition", "There is still time left.");
    revealTx(tx, deps, roomId, room, round, answer, null, "Time's up!");
    return { revealed: true };
  });
}

/** The current charades round (for nextRound and leaving), if any. */
export async function currentCharades(tx: Transaction, db: Firestore, roomId: string, key: string | null) {
  if (!key) return null;
  return ((await tx.get(charadesRef(db, roomId, key))).data() as CharadesRoundDoc | undefined) ?? null;
}

/** When the actor leaves mid-round, the round ends without points. */
export function charadesLeaveEffects(tx: Transaction, deps: Deps, roomId: string, round: CharadesRoundDoc | null, uid: string) {
  if (!round || round.status !== "acting" || round.actor !== uid) return;
  tx.update(charadesRef(deps.db, roomId, round.roundKey), {
    status: "revealed",
    scores: {},
    endedReason: "The actor left.",
    endedAt: Timestamp.fromMillis(deps.now()),
  });
}
