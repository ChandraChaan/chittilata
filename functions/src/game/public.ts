import { Timestamp } from "firebase-admin/firestore";
import { cleanAvatar, cleanPlayerName } from "../engine";
import type { Deps } from "./ops";
import { createRoom, roomRef } from "./ops";
import { PUBLIC_MATCH_MINUTES, PUBLIC_TABLE, RoomDoc } from "./model";

/**
 * Words that don't belong in a name shown to strangers. Basic on purpose:
 * chat is preset-only, so names are the only free text in public rooms.
 */
const BLOCKED = [
  "fuck", "shit", "bitch", "bastard", "asshole", "dick", "pussy", "cunt", "slut", "whore", "nigg", "rape",
  "porn", "sex", "lanja", "dengu", "puku", "modda", "gudda", "kojja", "randi", "chutiya", "madarchod",
  "behenchod", "bhosdi", "lund", "gandu",
];

/** A stranger-safe version of [name] ("Player 3" if it has a blocked word). */
export function publicName(name: string, seat: number): string {
  const flat = name.toLowerCase().replace(/[^a-z]/g, "");
  return BLOCKED.some((w) => flat.includes(w)) ? `Player ${seat}` : name;
}

/**
 * Quick match: joins the oldest open public table for [mode], or opens a
 * new one. Strangers only ever see each other's names, avatars and preset
 * chat.
 */
export async function quickMatch(deps: Deps, uid: string, data: unknown) {
  const { db, now } = deps;
  const d = (data ?? {}) as Record<string, unknown>;
  const mode = d.mode === "kingQueen" ? "kingQueen" : "movie";
  const name = cleanPlayerName(d.name);
  const avatar = cleanAvatar(d.avatar);
  const since = Timestamp.fromMillis(now() - PUBLIC_MATCH_MINUTES * 60 * 1000);
  const open = await db
    .collection("rooms")
    .where("public", "==", true)
    .where("status", "==", "lobby")
    .where("mode", "==", mode)
    .where("createdAt", ">=", since)
    .orderBy("createdAt")
    .limit(10)
    .get();
  for (const doc of open.docs) {
    const joined = await db.runTransaction(async (tx) => {
      const snap = await tx.get(roomRef(db, doc.id));
      const room = snap.data() as RoomDoc | undefined;
      if (!room || room.status !== "lobby" || !room.public || room.banned.includes(uid)) return null;
      if (room.memberUids.includes(uid)) return { roomId: doc.id, code: room.code };
      if (room.memberUids.length >= PUBLIC_TABLE) return null;
      // Same name as someone there: number it ("Ravi 2").
      const taken = new Set(room.memberUids.map((m) => room.players[m].name.toLowerCase()));
      let shown = publicName(name, room.memberUids.length + 1);
      for (let n = 2; taken.has(shown.toLowerCase()); n++) shown = `${name.slice(0, 13)} ${n}`;
      tx.update(snap.ref, {
        memberUids: [...room.memberUids, uid],
        [`players.${uid}`]: { name: shown, joinedAt: now(), ready: false, left: false, ...(avatar ? { avatar } : {}) },
        updatedAt: Timestamp.fromMillis(now()),
      });
      return { roomId: doc.id, code: room.code };
    });
    if (joined) return { ...joined, created: false };
  }
  const created = await createRoom(deps, uid, { name, mode, avatar, public: true });
  return { roomId: created.roomId, code: created.code, created: true };
}
