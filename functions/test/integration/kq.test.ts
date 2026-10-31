import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { GameError, seededRng } from "../../src/engine";
import * as kq from "../../src/game/kq";
import { RoomDoc } from "../../src/game/model";
import * as ops from "../../src/game/ops";

const PROJECT = "demo-chittilata-kq";
let db: Firestore;
let clock = 1_900_000_000_000;
let seed = 11;
const deps = (): ops.Deps => ({ db, now: () => clock, rng: seededRng(seed++) });

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run via firebase emulators:exec");
  db = getFirestore(initializeApp({ projectId: PROJECT }, "kq-test"));
});
afterAll(async () => {
  for (const app of getApps()) await deleteApp(app);
});
beforeEach(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {
    method: "DELETE",
  });
});

const room = async (id: string) => (await db.doc(`rooms/${id}`).get()).data() as RoomDoc;
const kround = async (id: string, key: string) =>
  (await db.doc(`rooms/${id}/kqRounds/${key}`).get()).data() as kq.KqRoundDoc;
const role = async (id: string, uid: string) => (await db.doc(`rooms/${id}/kqRoles/${uid}`).get()).data() as kq.KqRoleDoc;

async function expectCode(p: Promise<unknown>, code: GameError["code"]) {
  await expect(p).rejects.toSatisfy((e: unknown) => e instanceof GameError && e.code === code);
}

/** Heartbeats for [uids] as the app writes them, seen at [at]. */
async function online(roomId: string, uids: string[], at: number) {
  for (const u of uids) {
    await db.doc(`rooms/${roomId}/presence/${u}`).set({ lastSeen: Timestamp.fromMillis(at), state: "foreground" });
  }
}

const NAMES = ["Chandra", "Vasavi", "Swetha", "Sai", "Ravi", "Lata", "Kiran", "Anu", "Meena", "Gopi"];

async function kqLobby(n: number, settings?: Record<string, unknown>) {
  const uids = Array.from({ length: n }, (_, i) => `u${i}`);
  const { roomId, code } = await ops.createRoom(deps(), "u0", { name: NAMES[0], mode: "kingQueen" });
  for (let i = 1; i < n; i++) {
    await ops.joinRoom(deps(), uids[i], { code, name: NAMES[i] });
    await ops.setReady(deps(), uids[i], { roomId, ready: true });
  }
  if (settings) await ops.updateSettings(deps(), "u0", { roomId, kqSettings: settings });
  return { roomId, uids };
}

async function pickAll(roomId: string, key: string) {
  let r = await kround(roomId, key);
  clock = Math.max(clock, r.pickOpensAt.toMillis() + 1);
  for (const u of r.players) {
    r = await kround(roomId, key);
    if (Object.values(r.picks).includes(u)) continue;
    const free = r.chits.find((c) => !r.picks[c])!;
    await kq.kqPickChit(deps(), u, { roomId, roundKey: key, chitId: free });
  }
  r = await kround(roomId, key);
  clock = r.guessOpensAt!.toMillis() + 1;
  return r;
}

async function started(n: number, settings?: Record<string, unknown>) {
  const l = await kqLobby(n, settings);
  const { roundKey } = await ops.startGame(deps(), "u0", { roomId: l.roomId });
  return { ...l, roundKey };
}

/** The server's secret role map (tests may read it; clients never can). */
const secretRoles = async (roomId: string, key: string) =>
  ((await db.doc(`rooms/${roomId}/secrets/${key}`).get()).data() as { kqRoles: Record<string, number> }).kqRoles;

/** Plays a round to the end with seeded random guesses. */
async function playRound(roomId: string, key: string, rngSeed: number) {
  const rng = seededRng(rngSeed);
  for (let i = 0; i < 100; i++) {
    const r = await kround(roomId, key);
    if (r.status !== "guessing") return r;
    const out = new Set([...Object.keys(r.locked), r.guesser!, ...r.excluded]);
    const c = r.players.filter((p) => !out.has(p));
    await kq.kqGuess(deps(), r.guesser!, {
      roomId,
      roundKey: key,
      turnId: r.turnId,
      targetUid: c[rng(c.length)],
      requestId: `g-${key}-${r.turnId}`,
    });
    clock += 1000;
  }
  throw new Error("round did not end");
}

describe("King & Queen lobby", () => {
  it("creates a King & Queen room with default roles", async () => {
    const { roomId } = await kqLobby(1);
    const r = await room(roomId);
    expect(r.mode).toBe("kingQueen");
    expect(r.kqSettings!.roles.map((x) => x.name).slice(0, 2)).toEqual(["King", "Queen"]);
  });

  it("only the host changes settings; invalid points are refused", async () => {
    const { roomId } = await kqLobby(4);
    await expectCode(ops.updateSettings(deps(), "u1", { roomId, kqSettings: { rounds: 3 } }), "permission-denied");
    await expectCode(
      ops.updateSettings(deps(), "u0", { roomId, kqSettings: { roles: [{ key: "king", points: -5 }] } }),
      "invalid-argument",
    );
    const res = (await ops.updateSettings(deps(), "u0", {
      roomId,
      kqSettings: { rounds: 3, roles: [{ key: "king", points: 1200 }] },
    })) as { kqSettings: kq.KqSettings };
    expect(res.kqSettings.rounds).toBe(3);
    expect(res.kqSettings.roles[0].points).toBe(1200);
  });

  it("needs at least 4 players", async () => {
    const { roomId } = await kqLobby(3);
    await expect(ops.startGame(deps(), "u0", { roomId })).rejects.toThrow(/4-10 players/);
  });
});

describe("King & Queen picking", () => {
  it("deals sealed chits; nothing secret is public", async () => {
    const { roomId, roundKey, uids } = await started(5);
    const r = await kround(roomId, roundKey);
    expect(r.status).toBe("picking");
    expect(r.chain).toEqual(["King", "Queen", "Minister", "Police", "Thief"]);
    expect(r.chits).toHaveLength(5);
    expect(r.revealedRoles).toBeNull();
    for (const u of uids) expect((await role(roomId, u)).index).toBeNull();
    await expectCode(kq.kqPickChit(deps(), "u1", { roomId, roundKey, chitId: r.chits[0] }), "failed-precondition");
  });

  it("each player picks exactly one chit; every role is assigned once", async () => {
    const { roomId, roundKey, uids } = await started(4);
    let r = await kround(roomId, roundKey);
    clock = r.pickOpensAt.toMillis() + 1;
    const first = await kq.kqPickChit(deps(), "u1", { roomId, roundKey, chitId: r.chits[0] });
    expect(["King", "Queen", "Police", "Thief"]).toContain(first.role.name);
    expect((await role(roomId, "u1")).name).toBe(first.role.name);
    const again = await kq.kqPickChit(deps(), "u1", { roomId, roundKey, chitId: r.chits[0] });
    expect(again.duplicate).toBe(true);
    await expectCode(kq.kqPickChit(deps(), "u1", { roomId, roundKey, chitId: r.chits[1] }), "failed-precondition");
    await expectCode(kq.kqPickChit(deps(), "u2", { roomId, roundKey, chitId: r.chits[0] }), "already-exists");
    await expectCode(kq.kqPickChit(deps(), "outsider", { roomId, roundKey, chitId: r.chits[1] }), "permission-denied");
    await expectCode(kq.kqPickChit(deps(), "u2", { roomId, roundKey, chitId: "nope" }), "invalid-argument");
    r = await pickAll(roomId, roundKey);
    expect(r.status).toBe("guessing");
    const names = await Promise.all(uids.map(async (u) => (await role(roomId, u)).name));
    expect(names.sort()).toEqual(["King", "Police", "Queen", "Thief"]);
    // The King is announced publicly and guesses first.
    const indices = await Promise.all(uids.map(async (u) => [u, (await role(roomId, u)).index] as const));
    expect(r.guesser).toBe(indices.find(([, i]) => i === 0)![0]);
  });

  it("simultaneous grabs of one chit: exactly one player gets it", async () => {
    const { roomId, roundKey, uids } = await started(4);
    const r = await kround(roomId, roundKey);
    clock = r.pickOpensAt.toMillis() + 1;
    const results = await Promise.allSettled(
      uids.map((u) => kq.kqPickChit(deps(), u, { roomId, roundKey, chitId: r.chits[2] })),
    );
    expect(results.filter((x) => x.status === "fulfilled")).toHaveLength(1);
  });

  it("picks for slow players only after 45s of overtime, or when they are all offline", async () => {
    const { roomId, roundKey, uids } = await started(4);
    const r = await kround(roomId, roundKey);
    clock = r.pickOpensAt.toMillis() + 1;
    await kq.kqPickChit(deps(), "u3", { roomId, roundKey, chitId: r.chits[0] });
    await expectCode(kq.kqAutoPick(deps(), "u0", { roomId, roundKey }), "failed-precondition");
    clock = r.pickDeadline.toMillis() + 1500;
    await online(roomId, uids, clock);
    await expectCode(kq.kqAutoPick(deps(), "u0", { roomId, roundKey }), "failed-precondition");
    await online(roomId, ["u1", "u2"], clock - 60_000);
    await expectCode(kq.kqAutoPick(deps(), "u3", { roomId, roundKey }), "failed-precondition"); // u0 still online
    await online(roomId, ["u0"], clock - 60_000);
    expect((await kq.kqAutoPick(deps(), "u0", { roomId, roundKey })).assigned).toBe(3);
    expect((await kround(roomId, roundKey)).status).toBe("guessing");
  });
});

describe("King & Queen guessing", () => {
  it("rejects guesses before the announcement, out of turn and at invalid targets", async () => {
    const { roomId, roundKey } = await started(4);
    let r = await kround(roomId, roundKey);
    clock = r.pickOpensAt.toMillis() + 1;
    for (const u of r.players) {
      r = await kround(roomId, roundKey);
      await kq.kqPickChit(deps(), u, { roomId, roundKey, chitId: r.chits.find((c) => !r.picks[c])! });
    }
    r = await kround(roomId, roundKey);
    const king = r.guesser!;
    const other = r.players.find((p) => p !== king)!;
    await expectCode(
      kq.kqGuess(deps(), king, { roomId, roundKey, turnId: 0, targetUid: other, requestId: "early" }),
      "failed-precondition",
    );
    clock = r.guessOpensAt!.toMillis() + 1;
    await expectCode(
      kq.kqGuess(deps(), other, { roomId, roundKey, turnId: 0, targetUid: king, requestId: "x" }),
      "permission-denied",
    );
    await expectCode(
      kq.kqGuess(deps(), king, { roomId, roundKey, turnId: 0, targetUid: king, requestId: "self" }),
      "invalid-argument",
    );
    await expectCode(
      kq.kqGuess(deps(), "outsider", { roomId, roundKey, turnId: 0, targetUid: king, requestId: "o" }),
      "permission-denied",
    );
  });

  it("a correct guess locks the King; a wrong one swaps roles privately and passes the turn", async () => {
    const { roomId, roundKey } = await started(4);
    const r = await pickAll(roomId, roundKey);
    const roles = await secretRoles(roomId, roundKey);
    const king = r.guesser!;
    const wrong = r.players.find((p) => roles[p] >= 2)!;
    const before = (await role(roomId, wrong)).name;
    await kq.kqGuess(deps(), king, { roomId, roundKey, turnId: 0, targetUid: wrong, requestId: "w" });
    const r1 = await kround(roomId, roundKey);
    expect(r1.guesser).toBe(wrong); // the new King guesses next
    expect(r1.step).toBe(0);
    expect(r1.excluded).toEqual([king]);
    expect((await role(roomId, wrong)).name).toBe("King");
    expect((await role(roomId, king)).name).toBe(before);
    expect(r1.history[0]).toMatchObject({ guesser: king, target: wrong, correct: false });
    // Public state never shows the old King's new role.
    expect(JSON.stringify(r1)).not.toContain(`"${king}":${roles[wrong]}`);

    const roles1 = await secretRoles(roomId, roundKey);
    const queen = r1.players.find((p) => roles1[p] === 1)!;
    await kq.kqGuess(deps(), wrong, { roomId, roundKey, turnId: r1.turnId, targetUid: queen, requestId: "c" });
    const r2 = await kround(roomId, roundKey);
    expect(r2.locked[wrong]).toBe(0);
    expect(r2.guesser === queen || r2.status === "revealed").toBe(true);
  });

  it("replayed requests change nothing; competing guesses apply once", async () => {
    const { roomId, roundKey } = await started(5);
    const r = await pickAll(roomId, roundKey);
    const king = r.guesser!;
    const others = r.players.filter((p) => p !== king);
    const args = { roomId, roundKey, turnId: 0, targetUid: others[0], requestId: "same" };
    await kq.kqGuess(deps(), king, args);
    const after = await kround(roomId, roundKey);
    expect((await kq.kqGuess(deps(), king, args)).duplicate).toBe(true);
    expect((await kround(roomId, roundKey)).turnId).toBe(after.turnId);

    const { roomId: r2Id, roundKey: k2 } = await started(5);
    const r2 = await pickAll(r2Id, k2);
    const k = r2.guesser!;
    const targets = r2.players.filter((p) => p !== k);
    const results = await Promise.allSettled(
      targets.map((t, i) => kq.kqGuess(deps(), k, { roomId: r2Id, roundKey: k2, turnId: 0, targetUid: t, requestId: `r${i}` })),
    );
    expect(results.filter((x) => x.status === "fulfilled")).toHaveLength(1);
    expect((await kround(r2Id, k2)).history.filter((h) => h.kind === "guess")).toHaveLength(1);
  });

  it("never auto-guesses: late guessers can still guess, others guess for them only after 45s", async () => {
    const { roomId, roundKey, uids } = await started(4);
    let r = await pickAll(roomId, roundKey);
    await expectCode(kq.kqClaimTimeout(deps(), "u1", { roomId, roundKey, turnId: 0 }), "failed-precondition");
    clock = r.turnDeadline!.toMillis() + 1500;
    await online(roomId, uids, clock);
    await expectCode(kq.kqClaimTimeout(deps(), "u1", { roomId, roundKey, turnId: 0 }), "failed-precondition");
    const target = r.players.find((p) => p !== r.guesser && !r.excluded.includes(p))!;
    await kq.kqGuess(deps(), r.guesser!, { roomId, roundKey, turnId: 0, targetUid: target, requestId: "late" });
    r = await kround(roomId, roundKey);
    expect(r.history[0].kind).toBe("guess");
    if (r.status === "revealed") return;

    clock = r.turnDeadline!.toMillis() + 46_000;
    await online(roomId, uids, clock);
    await kq.kqClaimTimeout(deps(), "u1", { roomId, roundKey, turnId: r.turnId });
    await expectCode(kq.kqClaimTimeout(deps(), "u2", { roomId, roundKey, turnId: r.turnId }), "failed-precondition");
    const played = (await kround(roomId, roundKey)).history[r.history.length];
    expect(played.kind).toBe("timeout");
    expect(played.guesser).toBe(r.guesser);
  });

  it("plays complete rounds: every role revealed once, points and King wins recorded", async () => {
    for (const n of [4, 6, 10]) {
      const { roomId, roundKey, uids } = await started(n, { rounds: 2 });
      await pickAll(roomId, roundKey);
      const done = await playRound(roomId, roundKey, n);
      expect(done.status).toBe("revealed");
      const idx = Object.values(done.revealedRoles!).sort((a, b) => a - b);
      expect(idx).toEqual([...Array(n).keys()]);
      expect(Object.keys(done.locked).sort()).toEqual(uids.slice().sort());
      const total = Object.values(done.scores!).reduce((a, b) => a + b, 0);
      expect(total).toBe(done.chainPoints.reduce((a, b) => a + b, 0));
      const rm = await room(roomId);
      const king = uids.find((u) => done.revealedRoles![u] === 0)!;
      expect(rm.kingWins![king]).toBe(1);
      for (const u of uids) {
        expect(rm.totals[u]).toBe(done.scores![u]);
        expect((await role(roomId, u)).index).toBe(done.revealedRoles![u]);
      }
      expect(done.history.length).toBeLessThanOrEqual((n * (n - 1)) / 2);
      await expectCode(
        kq.kqGuess(deps(), uids[0], { roomId, roundKey, turnId: done.turnId, targetUid: uids[1], requestId: "after" }),
        "failed-precondition",
      );
    }
  });

  it("finishes the game after the last round with King-wins as the tie-break", async () => {
    const { roomId } = await started(4, { rounds: 2 });
    let key = (await room(roomId)).currentRoundKey!;
    await pickAll(roomId, key);
    await playRound(roomId, key, 1);
    await expectCode(ops.nextRound(deps(), "u1", { roomId }), "permission-denied");
    key = (await ops.nextRound(deps(), "u0", { roomId })).roundKey;
    await pickAll(roomId, key);
    await playRound(roomId, key, 2);
    const rm = await room(roomId);
    expect(rm.status).toBe("finished");
    expect(rm.final).toHaveLength(4);
    expect(rm.final![0].title).toBe("King");
    const sum = Object.values(rm.totals).reduce((a, b) => a + b, 0);
    expect(sum).toBe(2 * (1000 + 800 + 500 + 100));
    // Ranking key 2 is rounds finished as King.
    for (const s of rm.final!) expect(s.movieWins).toBe(rm.kingWins![s.uid] ?? 0);
    await expectCode(ops.nextRound(deps(), "u0", { roomId }), "failed-precondition");
  });
});

describe("King & Queen leaving", () => {
  it("leaving mid-round voids it; fewer than 4 players ends the game", async () => {
    const { roomId, roundKey } = await started(5);
    await pickAll(roomId, roundKey);
    await ops.leaveRoom(deps(), "u4", { roomId });
    expect((await kround(roomId, roundKey)).status).toBe("aborted");
    expect((await room(roomId)).status).toBe("playing");
    const next = await ops.nextRound(deps(), "u0", { roomId });
    expect((await kround(roomId, next.roundKey)).players).toHaveLength(4);
    await ops.leaveRoom(deps(), "u3", { roomId });
    const rm = await room(roomId);
    expect(rm.status).toBe("finished");
    expect((await kround(roomId, next.roundKey)).status).toBe("aborted");
  });
});

describe("Movie Chits rooms are unaffected", () => {
  it("default mode is movie and King & Queen calls are refused there", async () => {
    const { roomId, code } = await ops.createRoom(deps(), "m0", { name: "Host" });
    expect((await room(roomId)).mode).toBe("movie");
    for (let i = 1; i < 4; i++) {
      await ops.joinRoom(deps(), `m${i}`, { code, name: `P${i}` });
      await ops.setReady(deps(), `m${i}`, { roomId, ready: true });
    }
    const { roundKey } = await ops.startGame(deps(), "m0", { roomId });
    await expectCode(kq.kqPickChit(deps(), "m1", { roomId, roundKey, chitId: "x" }), "failed-precondition");
    expect((await db.doc(`rooms/${roomId}/rounds/${roundKey}`).get()).get("status")).toBe("picking");
  });
});
