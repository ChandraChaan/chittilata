import { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { cleanAvatar, cleanPlayerName, randomId, roomCode } from "../engine";
import type { Deps } from "./ops";
import { fail, str } from "./ops";
import type { RoomDoc } from "./model";

/**
 * Friend groups ("Family", "Office gang"): a saved circle of players with a
 * running leaderboard per calendar month (India time). Rooms created for a
 * group add every group member's game points to that month's season.
 *
 *   groups/{groupId}                  name, code, members (members only)
 *   groups/{groupId}/seasons/{YYYY-MM} points, games, titles per member
 *   groupCodes/{code}                 code -> groupId (server only)
 */
export interface GroupDoc {
  name: string;
  code: string;
  ownerUid: string;
  memberUids: string[];
  members: Record<string, { name: string; avatar: string | null; joinedAt: number }>;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface SeasonDoc {
  season: string;
  points: Record<string, number>;
  games: Record<string, number>;
  kings: Record<string, number>;
  queens: Record<string, number>;
  /** "roomId:gameNo" of games already counted (each counts once). */
  counted: string[];
  updatedAt: Timestamp;
}

export const MAX_GROUP_MEMBERS = 50;
export const MAX_GROUPS_PER_PLAYER = 10;

/** The season (calendar month in India) a time belongs to, e.g. "2026-11". */
export const seasonOf = (t: number) => new Date(t + 5.5 * 3600 * 1000).toISOString().slice(0, 7);

const groupRef = (db: Firestore, id: string) => db.collection("groups").doc(id);
const seasonRef = (db: Firestore, id: string, season: string) => groupRef(db, id).collection("seasons").doc(season);

function cleanGroupName(value: unknown): string {
  if (typeof value !== "string") fail("invalid-argument", "Give the group a name.");
  const s = (value as string).replace(/\s+/g, " ").trim();
  if (!s) fail("invalid-argument", "Give the group a name.");
  if (s.length > 24) fail("invalid-argument", "Group names can be at most 24 characters.");
  return s;
}

async function groupsOf(tx: Transaction, db: Firestore, uid: string) {
  return (await tx.get(db.collection("groups").where("memberUids", "array-contains", uid))).size;
}

export async function createGroup(deps: Deps, uid: string, data: unknown) {
  const { db, now, rng } = deps;
  const d = data as Record<string, unknown> | null;
  const name = cleanGroupName(d?.name);
  const playerName = cleanPlayerName(d?.playerName);
  const avatar = cleanAvatar(d?.avatar);
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = roomCode(rng);
    const codeRef = db.collection("groupCodes").doc(code);
    const id = `g${randomId(rng, 16)}`;
    const ok = await db.runTransaction(async (tx) => {
      if ((await tx.get(codeRef)).exists) return false;
      if ((await groupsOf(tx, db, uid)) >= MAX_GROUPS_PER_PLAYER) {
        fail("resource-exhausted", `You can be in at most ${MAX_GROUPS_PER_PLAYER} groups.`);
      }
      const ts = Timestamp.fromMillis(now());
      const group: GroupDoc = {
        name,
        code,
        ownerUid: uid,
        memberUids: [uid],
        members: { [uid]: { name: playerName, avatar, joinedAt: now() } },
        createdAt: ts,
        updatedAt: ts,
      };
      tx.create(groupRef(db, id), group);
      tx.create(codeRef, { groupId: id, createdAt: ts });
      return true;
    });
    if (ok) return { groupId: id, code };
  }
  return fail("resource-exhausted", "Could not make a group code. Try again.");
}

export async function joinGroup(deps: Deps, uid: string, data: unknown) {
  const { db, now } = deps;
  const d = data as Record<string, unknown> | null;
  const code = str(data, "code", 12).trim().toUpperCase();
  const playerName = cleanPlayerName(d?.playerName);
  const avatar = cleanAvatar(d?.avatar);
  const codeSnap = await db.collection("groupCodes").doc(code).get();
  if (!codeSnap.exists) fail("not-found", "No group with that code.");
  const groupId = codeSnap.get("groupId") as string;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(groupRef(db, groupId));
    if (!snap.exists) fail("not-found", "That group no longer exists.");
    const g = snap.data() as GroupDoc;
    const member = { name: playerName, avatar, joinedAt: g.members[uid]?.joinedAt ?? now() };
    if (g.memberUids.includes(uid)) {
      tx.update(snap.ref, { [`members.${uid}`]: member });
      return;
    }
    if (g.memberUids.length >= MAX_GROUP_MEMBERS) fail("resource-exhausted", "This group is full.");
    if ((await groupsOf(tx, db, uid)) >= MAX_GROUPS_PER_PLAYER) {
      fail("resource-exhausted", `You can be in at most ${MAX_GROUPS_PER_PLAYER} groups.`);
    }
    tx.update(snap.ref, {
      memberUids: [...g.memberUids, uid],
      [`members.${uid}`]: member,
      updatedAt: Timestamp.fromMillis(now()),
    });
  });
  return { groupId };
}

/** Leaving keeps past seasons; the last member leaving deletes the group. */
export async function leaveGroup(deps: Deps, uid: string, data: unknown) {
  const { db, now } = deps;
  const groupId = str(data, "groupId");
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(groupRef(db, groupId));
    if (!snap.exists) return;
    const g = snap.data() as GroupDoc;
    if (!g.memberUids.includes(uid)) return;
    const memberUids = g.memberUids.filter((m) => m !== uid);
    if (memberUids.length === 0) {
      tx.delete(snap.ref);
      tx.delete(db.collection("groupCodes").doc(g.code));
      return;
    }
    tx.update(snap.ref, {
      memberUids,
      ownerUid: g.ownerUid === uid ? memberUids[0] : g.ownerUid,
      updatedAt: Timestamp.fromMillis(now()),
    });
  });
  return { ok: true };
}

/** For createRoom: the group's name if [uid] may start a game for it. */
export async function groupForRoom(tx: Transaction, db: Firestore, uid: string, groupId: unknown) {
  if (groupId === undefined || groupId === null) return null;
  if (typeof groupId !== "string" || groupId.length > 64) fail("invalid-argument", "Unknown group.");
  const snap = await tx.get(groupRef(db, groupId as string));
  const g = snap.data() as GroupDoc | undefined;
  if (!g || !g.memberUids.includes(uid)) fail("permission-denied", "You're not in that group.");
  return { groupId: groupId as string, groupName: g!.name };
}

/**
 * Adds a finished game to its group's season (once). Only group members
 * count; points are the game totals, plus the King/Queen titles.
 */
export async function recordGroupGame(db: Firestore, roomId: string, room: RoomDoc, t: number) {
  const groupId = room.groupId;
  if (!groupId || !room.final) return { recorded: false };
  const key = `${roomId}:${room.gameNo}`;
  const season = seasonOf(t);
  return db.runTransaction(async (tx) => {
    const [gSnap, sSnap] = await Promise.all([tx.get(groupRef(db, groupId)), tx.get(seasonRef(db, groupId, season))]);
    const g = gSnap.data() as GroupDoc | undefined;
    if (!g) return { recorded: false };
    const s = sSnap.data() as SeasonDoc | undefined;
    if (s?.counted.includes(key)) return { recorded: false };
    const next: SeasonDoc = {
      season,
      points: { ...s?.points },
      games: { ...s?.games },
      kings: { ...s?.kings },
      queens: { ...s?.queens },
      counted: [...(s?.counted ?? []), key].slice(-500),
      updatedAt: Timestamp.fromMillis(t),
    };
    const add = (m: Record<string, number>, uid: string, n: number) => (m[uid] = (m[uid] ?? 0) + n);
    for (const st of room.final!) {
      if (!g.memberUids.includes(st.uid)) continue;
      add(next.points, st.uid, st.total);
      add(next.games, st.uid, 1);
      if (st.title === "King") add(next.kings, st.uid, 1);
      if (st.title === "Queen") add(next.queens, st.uid, 1);
    }
    tx.set(sSnap.ref, next);
    return { recorded: true };
  });
}
