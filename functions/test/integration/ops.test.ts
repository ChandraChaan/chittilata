import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { Card, GameError, seededRng } from "../../src/engine";
import { HandDoc, RoomDoc, RoundDoc } from "../../src/game/model";
import * as ops from "../../src/game/ops";

const PROJECT = "demo-chittilata-ops";
let db: Firestore;
let clock = 1_800_000_000_000;
let seed = 1;
const deps = (): ops.Deps => ({ db, now: () => clock, rng: seededRng(seed++) });

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run via firebase emulators:exec");
  const app = initializeApp({ projectId: PROJECT }, "ops-test");
  db = getFirestore(app);
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
const round = async (id: string, key: string) => (await db.doc(`rooms/${id}/rounds/${key}`).get()).data() as RoundDoc;
const hand = async (id: string, uid: string) => (await db.doc(`rooms/${id}/hands/${uid}`).get()).data() as HandDoc;

async function expectCode(p: Promise<unknown>, code: GameError["code"]) {
  await expect(p).rejects.toSatisfy((e: unknown) => e instanceof GameError && e.code === code);
}

async function lobby(n: number) {
  const uids = Array.from({ length: n }, (_, i) => `u${i}`);
  const { roomId, code } = await ops.createRoom(deps(), uids[0], { name: "Chandra" });
  const names = ["Chandra", "Vasavi", "Swetha", "Sai", "Ravi", "Lata", "Kiran", "Anu", "Meena", "Gopi"];
  for (let i = 1; i < n; i++) {
    await ops.joinRoom(deps(), uids[i], { code, name: names[i] });
    await ops.setReady(deps(), uids[i], { roomId, ready: true });
  }
  return { roomId, code, uids };
}

async function started(n: number) {
  const l = await lobby(n);
  const { roundKey } = await ops.startGame(deps(), l.uids[0], { roomId: l.roomId });
  clock += 6000; // past the intro
  return { ...l, roundKey };
}

/** Greedy bot: pass a card of the name it holds fewest of. */
function botCard(cards: Card[]): string {
  const counts = new Map<string, number>();
  cards.forEach((c) => counts.set(c.name, (counts.get(c.name) ?? 0) + 1));
  return cards.slice().sort((a, b) => counts.get(a.name)! - counts.get(b.name)!)[0].id;
}

async function playUntilWin(roomId: string, roundKey: string) {
  for (let i = 0; i < 2000; i++) {
    const r = await round(roomId, roundKey);
    if (r.status !== "exchange") return r;
    const h = await hand(roomId, r.currentUid);
    await ops.passCard(deps(), r.currentUid, {
      roomId,
      roundKey,
      turnId: r.turnId,
      cardId: botCard(h.cards),
      requestId: `req-${roundKey}-${r.turnId}`,
    });
    clock += 1000;
  }
  throw new Error("no winner");
}

describe("lobby", () => {
  it("creates a room with a 6-character code and the creator as host", async () => {
    const { roomId, code, uids } = await lobby(1);
    expect(code).toMatch(/^[A-Z2-9]{6}$/);
    const r = await room(roomId);
    expect(r.hostUid).toBe(uids[0]);
    expect(r.memberUids).toEqual([uids[0]]);
    expect(r.status).toBe("lobby");
  });

  it("joining twice does not duplicate the player", async () => {
    const { roomId, code } = await lobby(2);
    await ops.joinRoom(deps(), "u1", { code, name: "Vasavi" });
    expect((await room(roomId)).memberUids).toEqual(["u0", "u1"]);
  });

  it("rejects unknown codes, duplicate names and full rooms", async () => {
    const small = await lobby(3);
    await expectCode(ops.joinRoom(deps(), "x", { code: "NOPE22", name: "X" }), "not-found");
    await expectCode(ops.joinRoom(deps(), "x", { code: small.code, name: "swetha" }), "already-exists");
    const { code } = await lobby(10);
    await expectCode(ops.joinRoom(deps(), "x", { code, name: "Eleven" }), "resource-exhausted");
  });

  it("only the host can change settings or start", async () => {
    const { roomId } = await lobby(4);
    await expectCode(ops.updateSettings(deps(), "u1", { roomId, settings: { rounds: 3 } }), "permission-denied");
    await expectCode(ops.startGame(deps(), "u1", { roomId }), "permission-denied");
    const { settings } = await ops.updateSettings(deps(), "u0", { roomId, settings: { rounds: 3 } });
    expect(settings.rounds).toBe(3);
  });

  it("waits for everyone to be ready and for at least 3 players", async () => {
    const two = await lobby(2);
    await expectCode(ops.startGame(deps(), "u0", { roomId: two.roomId }), "failed-precondition");
    const four = await lobby(4);
    await ops.setReady(deps(), "u2", { roomId: four.roomId, ready: false });
    await expect(ops.startGame(deps(), "u0", { roomId: four.roomId })).rejects.toThrow(/Waiting for Swetha/);
  });

  it("kicked players cannot rejoin; nobody joins after the start", async () => {
    const { roomId, code } = await lobby(4);
    await ops.kickPlayer(deps(), "u0", { roomId, uid: "u3" });
    await expectCode(ops.joinRoom(deps(), "u3", { code, name: "Sai" }), "permission-denied");
    await ops.joinRoom(deps(), "u9", { code, name: "Gopi" });
    await ops.setReady(deps(), "u9", { roomId, ready: true });
    await ops.startGame(deps(), "u0", { roomId });
    await expectCode(ops.joinRoom(deps(), "late", { code, name: "Late" }), "failed-precondition");
  });

  it("host leaving in the lobby hands the room to the next player", async () => {
    const { roomId } = await lobby(3);
    await ops.leaveRoom(deps(), "u0", { roomId });
    const r = await room(roomId);
    expect(r.hostUid).toBe("u1");
    expect(r.players.u0).toBeUndefined();
  });
});

describe("dealing", () => {
  it("deals 4 diverse cards to everyone with a random full circle", async () => {
    const { roomId, roundKey, uids } = await started(4);
    const r = await round(roomId, roundKey);
    expect(r.order.slice().sort()).toEqual(uids.slice().sort());
    expect(r.movieNames).toHaveLength(4);
    const ids = new Set<string>();
    for (const u of uids) {
      const h = await hand(roomId, u);
      expect(h.cards).toHaveLength(4);
      expect(new Set(h.cards.map((c) => c.name)).size).toBe(4);
      h.cards.forEach((c) => ids.add(c.id));
    }
    expect(ids.size).toBe(16);
    // the public round document holds no card identities while active
    expect(JSON.stringify(r)).not.toMatch(/"cards"|"id":/);
    expect(r.revealedHands).toBeNull();
  });
});

describe("exchange", () => {
  it("passes a card, updates both hands, and advances the turn", async () => {
    const { roomId, roundKey } = await started(4);
    const r = await round(roomId, roundKey);
    const from = await hand(roomId, r.currentUid);
    const cardId = from.cards[0].id;
    await ops.passCard(deps(), r.currentUid, { roomId, roundKey, turnId: 0, cardId, requestId: "a" });
    const r2 = await round(roomId, roundKey);
    expect(r2.turnId).toBe(1);
    expect(r2.currentUid).toBe(r.nextUid);
    expect((await hand(roomId, r.currentUid)).cards).toHaveLength(3);
    const to = await hand(roomId, r.nextUid);
    expect(to.cards).toHaveLength(5);
    expect(to.incomingCardId).toBe(cardId);
    expect(r2.handSizes[r.nextUid]).toBe(5);
  });

  it("rejects out-of-turn, foreign-card and too-early passes", async () => {
    const l = await lobby(4);
    const { roundKey } = await ops.startGame(deps(), "u0", { roomId: l.roomId });
    const r = await round(l.roomId, roundKey);
    const mine = (await hand(l.roomId, r.currentUid)).cards[0].id;
    await expectCode(
      ops.passCard(deps(), r.currentUid, { roomId: l.roomId, roundKey, turnId: 0, cardId: mine, requestId: "e" }),
      "failed-precondition",
    ); // still in the intro
    clock += 6000;
    await expectCode(
      ops.passCard(deps(), r.nextUid, { roomId: l.roomId, roundKey, turnId: 0, cardId: mine, requestId: "x" }),
      "permission-denied",
    );
    const theirs = (await hand(l.roomId, r.nextUid)).cards[0].id;
    await expectCode(
      ops.passCard(deps(), r.currentUid, { roomId: l.roomId, roundKey, turnId: 0, cardId: theirs, requestId: "y" }),
      "invalid-argument",
    );
    await expectCode(
      ops.passCard(deps(), "outsider", { roomId: l.roomId, roundKey, turnId: 0, cardId: mine, requestId: "z" }),
      "permission-denied",
    );
  });

  it("a retried request is applied once", async () => {
    const { roomId, roundKey } = await started(4);
    const r = await round(roomId, roundKey);
    const cardId = (await hand(roomId, r.currentUid)).cards[0].id;
    const args = { roomId, roundKey, turnId: 0, cardId, requestId: "same" };
    const first = await ops.passCard(deps(), r.currentUid, args);
    const again = await ops.passCard(deps(), r.currentUid, args);
    expect(first.duplicate).toBe(false);
    expect(again.duplicate).toBe(true);
    expect((await round(roomId, roundKey)).turnId).toBe(1);
    expect((await hand(roomId, r.nextUid)).cards).toHaveLength(5);
  });

  it("simultaneous competing passes for one turn: exactly one wins", async () => {
    const { roomId, roundKey } = await started(4);
    const r = await round(roomId, roundKey);
    const cards = (await hand(roomId, r.currentUid)).cards;
    const results = await Promise.allSettled(
      cards.map((c, i) =>
        ops.passCard(deps(), r.currentUid, { roomId, roundKey, turnId: 0, cardId: c.id, requestId: `c${i}` }),
      ),
    );
    expect(results.filter((x) => x.status === "fulfilled")).toHaveLength(1);
    expect((await round(roomId, roundKey)).turnId).toBe(1);
    expect((await hand(roomId, r.currentUid)).cards).toHaveLength(3);
    expect((await hand(roomId, r.nextUid)).cards).toHaveLength(5);
  });

  it("timeouts only apply after the server deadline and pass the incoming card", async () => {
    const { roomId, roundKey } = await started(4);
    let r = await round(roomId, roundKey);
    const cardId = (await hand(roomId, r.currentUid)).cards[0].id;
    await ops.passCard(deps(), r.currentUid, { roomId, roundKey, turnId: 0, cardId, requestId: "t0" });
    r = await round(roomId, roundKey);
    const waiting = r.currentUid;
    await expectCode(ops.claimTimeout(deps(), "u0", { roomId, roundKey, turnId: 1 }), "failed-precondition");
    clock = r.turnDeadline.toMillis() + 1500;
    // the late player can no longer act
    const late = (await hand(roomId, waiting)).cards[0].id;
    await expectCode(
      ops.passCard(deps(), waiting, { roomId, roundKey, turnId: 1, cardId: late, requestId: "late" }),
      "failed-precondition",
    );
    await ops.claimTimeout(deps(), "u0", { roomId, roundKey, turnId: 1 });
    // a second claim for the same turn is rejected, not applied twice
    await expectCode(ops.claimTimeout(deps(), "u1", { roomId, roundKey, turnId: 1 }), "failed-precondition");
    const after = await round(roomId, roundKey);
    expect(after.lastAction?.type).toBe("timeout");
    expect(after.timeouts[waiting]).toBe(1);
    expect((await hand(roomId, r.nextUid)).incomingCardId).toBe(cardId);
  });
});

describe("full game", () => {
  it("plays rounds to a single winner, characters, reveal and final King/Queen", async () => {
    const { roomId, uids } = await lobby(4);
    await ops.updateSettings(deps(), "u0", { roomId, settings: { rounds: 2 } });
    let { roundKey } = await ops.startGame(deps(), "u0", { roomId });
    const orders: string[][] = [];

    for (let n = 1; n <= 2; n++) {
      clock += 6000;
      const won = await playUntilWin(roomId, roundKey);
      orders.push(won.order);
      expect(won.status).toBe("characters");
      const winner = won.winner!.uid;
      const winHand = await hand(roomId, winner);
      expect(winHand.character).toBeNull();
      const names = new Set<string>();
      for (const u of uids.filter((x) => x !== winner)) {
        const c = (await hand(roomId, u)).character!;
        expect(c).toBeTruthy();
        names.add(c.name);
      }
      expect([...names].sort()).toEqual(["Police", "Queen", "Thief"]);

      // stopped: no more passes
      await expectCode(
        ops.passCard(deps(), won.currentUid, { roomId, roundKey, turnId: won.turnId, cardId: "x", requestId: "after" }),
        "failed-precondition",
      );
      // reveal is gated by time for non-hosts
      const nonHost = uids.find((u) => u !== "u0")!;
      await expectCode(ops.revealRound(deps(), nonHost, { roomId, roundKey }), "failed-precondition");
      const before = await room(roomId);
      clock = won.revealAt!.toMillis() + 1;
      await ops.revealRound(deps(), nonHost, { roomId, roundKey });
      const again = await ops.revealRound(deps(), "u0", { roomId, roundKey });
      expect(again.alreadyRevealed).toBe(true);

      const done = await round(roomId, roundKey);
      expect(done.status).toBe("revealed");
      expect(Object.keys(done.revealedHands!).sort()).toEqual(uids.slice().sort());
      expect(done.scores![winner]).toBe(1000);
      const sum = Object.values(done.scores!).reduce((a, b) => a + b, 0);
      expect(sum).toBe(1000 + 800 + 500 + 100);
      const after = await room(roomId);
      for (const u of uids) {
        const char = done.characters![u]?.points ?? 0;
        expect(after.totals[u]).toBe((before.totals[u] ?? 0) + char);
      }
      if (n < 2) ({ roundKey } = await ops.nextRound(deps(), "u0", { roomId }));
    }

    const final = await room(roomId);
    expect(final.status).toBe("finished");
    expect(final.final).toHaveLength(4);
    expect(final.final![0].title).toBe("King");
    const grand = Object.values(final.totals).reduce((a, b) => a + b, 0);
    expect(grand).toBe(2 * 2400);
    await expectCode(ops.nextRound(deps(), "u0", { roomId }), "failed-precondition");

    await ops.playAgain(deps(), "u0", { roomId });
    const again = await room(roomId);
    expect(again.status).toBe("lobby");
    expect(again.gameNo).toBe(2);
    expect(again.totals).toEqual({});
  });

  it("a player leaving mid-round voids the round; dropping below 3 ends the game", async () => {
    const { roomId, roundKey } = await started(4);
    await ops.leaveRoom(deps(), "u3", { roomId });
    expect((await round(roomId, roundKey)).status).toBe("aborted");
    const r = await room(roomId);
    expect(r.players.u3.left).toBe(true);
    expect(r.memberUids).not.toContain("u3");
    const next = await ops.nextRound(deps(), "u0", { roomId });
    clock += 6000;
    expect((await round(roomId, next.roundKey)).order).toHaveLength(3);
    await ops.leaveRoom(deps(), "u0", { roomId });
    const ended = await room(roomId);
    expect(ended.status).toBe("finished");
    expect(ended.hostUid).not.toBe("u0");
  });

  it("closes stale rooms", async () => {
    const { roomId, code } = await lobby(3);
    clock += 25 * 3600 * 1000;
    expect(await ops.expireRooms(deps(), 24 * 3600 * 1000)).toBe(1);
    expect((await room(roomId)).status).toBe("closed");
    await expectCode(ops.joinRoom(deps(), "z", { code, name: "Z" }), "not-found");
  });
});
