import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { seededRng } from "../../src/engine";
import { RoomDoc } from "../../src/game/model";
import * as ops from "../../src/game/ops";
import * as groups from "../../src/game/groups";
import { deleteAccount } from "../../src/game/account";

const PROJECT = "demo-chittilata-account";
let db: Firestore;
const clock = 1_800_000_000_000;
let seed = 1;
const deps = (): ops.Deps => ({ db, now: () => clock, rng: seededRng(seed++) });

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run via firebase emulators:exec");
  db = getFirestore(initializeApp({ projectId: PROJECT }, "account-test"));
});

afterAll(async () => {
  for (const app of getApps()) await deleteApp(app);
});

beforeEach(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {
    method: "DELETE",
  });
});

describe("deleteAccount", () => {
  it("leaves rooms and groups, deletes the profile, push token and sign-in", async () => {
    const { roomId, code } = await ops.createRoom(deps(), "host", { name: "Host" });
    await ops.joinRoom(deps(), "alice", { code, name: "Alice" });
    const { groupId } = await groups.createGroup(deps(), "host", { name: "Family", playerName: "Host" });
    const g = (await db.doc(`groups/${groupId}`).get()).data()!;
    await groups.joinGroup(deps(), "alice", { code: g.code, playerName: "Alice" });
    // A group only Alice is in goes away with her.
    const { groupId: solo } = await groups.createGroup(deps(), "alice", { name: "Just me", playerName: "Alice" });
    await db.doc("users/alice").set({ counters: { games: 3 }, badges: [], seen: [], history: [] });
    await db.doc("pushTokens/alice").set({ token: "t" });
    await db.doc("users/host").set({ counters: { games: 9 }, badges: [], seen: [], history: [] });

    const removed: string[] = [];
    const res = await deleteAccount(deps(), "alice", async (uid) => {
      removed.push(uid);
    });

    expect(res).toMatchObject({ ok: true, rooms: 1, groups: 2 });
    expect(removed).toEqual(["alice"]);
    const room = (await db.doc(`rooms/${roomId}`).get()).data() as RoomDoc;
    expect(room.memberUids).toEqual(["host"]);
    expect(room.players.alice).toBeUndefined();
    const family = (await db.doc(`groups/${groupId}`).get()).data()!;
    expect(family.memberUids).toEqual(["host"]);
    expect(family.members.alice).toBeUndefined();
    expect(family.members.host.name).toBe("Host");
    expect((await db.doc(`groups/${solo}`).get()).exists).toBe(false);
    expect((await db.doc("users/alice").get()).exists).toBe(false);
    expect((await db.doc("pushTokens/alice").get()).exists).toBe(false);
    // Other players are untouched.
    expect((await db.doc("users/host").get()).exists).toBe(true);
  });

  it("works for a player with nothing saved, and when repeated", async () => {
    const noop = async () => {};
    await expect(deleteAccount(deps(), "nobody", noop)).resolves.toMatchObject({ rooms: 0, groups: 0 });
    await expect(deleteAccount(deps(), "nobody", noop)).resolves.toMatchObject({ ok: true });
  });
});
