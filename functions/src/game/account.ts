import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import type { Deps } from "./ops";
import { leaveRoom } from "./ops";
import { leaveGroup } from "./groups";

/** Deletes the Firebase Auth user (injected so tests need no Auth emulator). */
export type RemoveAuthUser = (uid: string) => Promise<void>;

/**
 * "Delete my account and data" (and switching a guest to an existing Google
 * player): takes [uid] out of every room and group it is in, removes its
 * name from those groups, deletes its cloud profile (`users/{uid}`) and push
 * token, then the sign-in itself. Finished rooms keep the name in past
 * results until they expire (see the privacy policy). Safe to repeat.
 */
export async function deleteAccount(deps: Deps, uid: string, removeAuthUser: RemoveAuthUser) {
  const { db } = deps;
  const rooms = new Set<string>();
  for (const field of ["memberUids", "spectatorUids"]) {
    const snap = await db.collection("rooms").where(field, "array-contains", uid).get();
    snap.docs.forEach((d) => rooms.add(d.id));
  }
  let failed = 0;
  for (const roomId of rooms) {
    try {
      await leaveRoom(deps, uid, { roomId });
    } catch (e) {
      failed++;
      logger.warn("deleteAccount: leaveRoom failed", { roomId, error: (e as Error).message });
    }
  }
  const groups = await db.collection("groups").where("memberUids", "array-contains", uid).get();
  for (const g of groups.docs) {
    try {
      await leaveGroup(deps, uid, { groupId: g.id });
      const left = await g.ref.get();
      if (left.exists) await g.ref.update({ [`members.${uid}`]: FieldValue.delete() });
    } catch (e) {
      failed++;
      logger.warn("deleteAccount: leaveGroup failed", { groupId: g.id, error: (e as Error).message });
    }
  }
  await db.collection("users").doc(uid).delete();
  await db.collection("pushTokens").doc(uid).delete();
  await removeAuthUser(uid);
  logger.info("deleteAccount", { rooms: rooms.size, groups: groups.size, failed });
  return { ok: true, rooms: rooms.size, groups: groups.size };
}
