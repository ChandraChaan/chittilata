import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { GameError, secureRng } from "./engine";
import * as ops from "./game/ops";
import * as kq from "./game/kq";
import { ROOM_TTL_HOURS } from "./game/model";

initializeApp();
setGlobalOptions({ region: "asia-south1", maxInstances: 20, memory: "256MiB" });

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
