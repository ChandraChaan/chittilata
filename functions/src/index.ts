import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as push from "./game/push";
import * as groups from "./game/groups";
import type { RoomDoc, RoundDoc } from "./game/model";
import type { KqRoundDoc } from "./game/kq";
import { GameError, secureRng } from "./engine";
import * as ops from "./game/ops";
import * as kq from "./game/kq";
import { ROOM_TTL_HOURS } from "./game/model";

initializeApp();
// Small, short transactions: a fractional CPU and few instances keep the
// project well inside its regional Cloud Run CPU quota.
setGlobalOptions({ region: "asia-south1", maxInstances: 5, memory: "256MiB", cpu: "gcf_gen1" });

const deps = (): ops.Deps => ({ db: getFirestore(), now: Date.now, rng: secureRng });

type Op = (deps: ops.Deps, uid: string, data: unknown) => Promise<object>;

/**
 * Wraps a game operation as an authenticated callable. Every response carries
 * `serverNow` so clients can align their countdowns to server deadlines.
 * Logs never include card names or hands.
 */
function callable(name: string, op: Op) {
  return onCall({ cors: false }, async (req: CallableRequest) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    try {
      const result = await op(deps(), uid, req.data);
      return { ...result, serverNow: Date.now() };
    } catch (e) {
      if (e instanceof GameError) throw new HttpsError(e.code, e.message);
      if (e instanceof HttpsError) throw e;
      logger.error(`${name} failed`, { uid, error: (e as Error).message });
      throw new HttpsError("internal", "Something went wrong. Please try again.");
    }
  });
}

export const createRoom = callable("createRoom", ops.createRoom);
export const joinRoom = callable("joinRoom", ops.joinRoom);
export const setReady = callable("setReady", ops.setReady);
export const updateSettings = callable("updateSettings", ops.updateSettings);
export const kickPlayer = callable("kickPlayer", ops.kickPlayer);
export const addBot = callable("addBot", ops.addBot);
export const claimSeat = callable("claimSeat", ops.claimSeat);
export const answerSeatClaim = callable("answerSeatClaim", ops.answerSeatClaim);
export const createGroup = callable("createGroup", groups.createGroup);
export const joinGroup = callable("joinGroup", groups.joinGroup);
export const leaveGroup = callable("leaveGroup", groups.leaveGroup);
export const leaveRoom = callable("leaveRoom", ops.leaveRoom);
export const startGame = callable("startGame", ops.startGame);
export const nextRound = callable("nextRound", ops.nextRound);
export const pickChit = callable("pickChit", ops.pickChit);
export const autoPickChits = callable("autoPickChits", ops.autoPickChits);
export const pickCharacter = callable("pickCharacter", ops.pickCharacter);
export const autoPickCharacters = callable("autoPickCharacters", ops.autoPickCharacters);
export const passCard = callable("passCard", ops.passCard);
export const claimTimeout = callable("claimTimeout", ops.claimTimeout);
export const revealRound = callable("revealRound", ops.revealRound);
export const playAgain = callable("playAgain", ops.playAgain);
export const tiebreakVote = callable("tiebreakVote", ops.tiebreakVote);
export const resolveTiebreakVote = callable("resolveTiebreakVote", ops.resolveTiebreakVote);
export const kqPickChit = callable("kqPickChit", kq.kqPickChit);
export const kqAutoPick = callable("kqAutoPick", kq.kqAutoPick);
export const kqGuess = callable("kqGuess", kq.kqGuess);
export const kqClaimTimeout = callable("kqClaimTimeout", kq.kqClaimTimeout);
export const ping = callable("ping", async () => ({}));

export const expireRooms = onSchedule({ schedule: "every 6 hours", timeZone: "Asia/Kolkata" }, async () => {
  const result = await ops.expireRooms(deps(), ROOM_TTL_HOURS * 3600 * 1000);
  logger.info("expireRooms", result);
});

// ---------- push notifications ----------

/** Sends pushes for one change; a failed push never affects the game. */
async function notify(roomId: string, make: (room: RoomDoc) => push.Push[]) {
  try {
    const db = getFirestore();
    const room = (await db.collection("rooms").doc(roomId).get()).data() as RoomDoc | undefined;
    if (!room || room.status === "closed") return;
    const pushes = make(room).filter((p) => room.memberUids.includes(p.uid));
    await push.deliver(db, getMessaging(), roomId, pushes, Date.now());
  } catch (e) {
    logger.warn("push failed", { roomId, error: (e as Error).message });
  }
}

export const pushOnRound = onDocumentWritten("rooms/{roomId}/rounds/{key}", async (event) => {
  const after = event.data?.after.data() as RoundDoc | undefined;
  if (!after) return;
  const before = event.data?.before.data() as RoundDoc | undefined;
  await notify(event.params.roomId, (room) => push.roundPushes(before, after, push.namesOf(room)));
});

export const pushOnKqRound = onDocumentWritten("rooms/{roomId}/kqRounds/{key}", async (event) => {
  const after = event.data?.after.data() as KqRoundDoc | undefined;
  if (!after) return;
  const before = event.data?.before.data() as KqRoundDoc | undefined;
  await notify(event.params.roomId, () => push.kqPushes(before, after));
});

/** Room status changes: tie-breaker pushes, and finished games count for groups. */
export const onRoomStatus = onDocumentWritten("rooms/{roomId}", async (event) => {
  const after = event.data?.after.data() as RoomDoc | undefined;
  const before = event.data?.before.data() as RoomDoc | undefined;
  if (!after || after.status === before?.status) return;
  if (after.status === "finished" && after.groupId) {
    try {
      await groups.recordGroupGame(getFirestore(), event.params.roomId, after, Date.now());
    } catch (e) {
      logger.error("group season failed", { roomId: event.params.roomId, error: (e as Error).message });
    }
  }
  await notify(event.params.roomId, () => push.roomPushes(before, after));
});

export const pushOnNudge = onDocumentWritten("rooms/{roomId}/chat/{uid}", async (event) => {
  const after = event.data?.after.data() as { kind?: string; to?: string | null } | undefined;
  if (after?.kind !== "nudge") return;
  await notify(event.params.roomId, (room) => push.nudgePush(after, event.params.uid, push.namesOf(room)));
});
