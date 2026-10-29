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

/** Every player picks 4 free chits through the real callable. */
async function pickAll(roomId: string, roundKey: string) {
  let r = await round(roomId, roundKey);
  clock = Math.max(clock, r.pickOpensAt.toMillis() + 1);
  for (const u of r.order) {
    for (let k = 0; k < 4; k++) {
      r = await round(roomId, roundKey);
      const free = r.chits.find((c) => !r.picks[c])!;
      await ops.pickChit(deps(), u, { roomId, roundKey, chitId: free });
    }
  }
  return round(roomId, roundKey);
}

/** Non-winners each pick one character chit; returns the round with revealAt. */
async function pickChars(roomId: string, roundKey: string) {
  let r = await round(roomId, roundKey);
  clock = Math.max(clock, r.charPickOpensAt!.toMillis() + 1);
  for (const u of r.order.filter((x) => x !== r.winner!.uid)) {
    r = await round(roomId, roundKey);
    const free = r.charChits.find((c) => !r.charPicks[c])!;
    await ops.pickCharacter(deps(), u, { roomId, roundKey, chitId: free });
  }
  return round(roomId, roundKey);
}

async function started(n: number) {
  const l = await lobby(n);
  const { roundKey } = await ops.startGame(deps(), l.uids[0], { roomId: l.roomId });
  await pickAll(l.roomId, roundKey);
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
    const r = await pickAll(l.roomId, roundKey);
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
      await pickAll(roomId, roundKey);
      clock += 6000;
      const won = await playUntilWin(roomId, roundKey);
      orders.push(won.order);
      expect(won.status).toBe("characters");
      expect(won.revealAt).toBeNull();
      const winner = won.winner!.uid;
      const picked = await pickChars(roomId, roundKey);
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
      clock = picked.revealAt!.toMillis() + 1;
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

    if ((await room(roomId)).status === "tiebreakVote") {
      // Random play happened to tie; decline so this test checks the plain finish.
      const tied = (await room(roomId)).tiebreak!.uids[0];
      await ops.tiebreakVote(deps(), tied, { roomId, accept: false });
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
    expect(await ops.expireRooms(deps(), 24 * 3600 * 1000)).toEqual({ closed: 1, deleted: 0 });
    expect((await room(roomId)).status).toBe("closed");
    await expectCode(ops.joinRoom(deps(), "z", { code, name: "Z" }), "not-found");
    // A week after closing, the room and its private subcollections are deleted.
    await db.doc(`rooms/${roomId}/hands/u1`).set({ cards: [] });
    clock += 8 * 24 * 3600 * 1000;
    expect(await ops.expireRooms(deps(), 24 * 3600 * 1000)).toEqual({ closed: 0, deleted: 1 });
    expect((await db.doc(`rooms/${roomId}`).get()).exists).toBe(false);
    expect((await db.doc(`rooms/${roomId}/hands/u1`).get()).exists).toBe(false);
  });
});

describe("tie-breaker", () => {
  /** Plays a 1-round game and rigs totals so the winner ties another player for King. */
  async function tiedGame() {
    const { roomId, uids } = await lobby(4);
    await ops.updateSettings(deps(), "u0", { roomId, settings: { rounds: 1 } });
    const { roundKey } = await ops.startGame(deps(), "u0", { roomId });
    await pickAll(roomId, roundKey);
    clock += 6000;
    const won = await playUntilWin(roomId, roundKey);
    const picked = await pickChars(roomId, roundKey);
    const winner = won.winner!.uid;
    const rival = uids.find((u) => u !== winner)!;
    const rivalChar = (await hand(roomId, rival)).character!.points;
    const totals = Object.fromEntries(uids.map((u) => [u, 0]));
    totals[winner] = 1000;
    totals[rival] = 1000 - rivalChar;
    const movieWins = Object.fromEntries(uids.map((u) => [u, 0]));
    movieWins[winner] = 1;
    movieWins[rival] = 1;
    await db.doc(`rooms/${roomId}`).update({ totals, movieWins });
    clock = picked.revealAt!.toMillis() + 1;
    await ops.revealRound(deps(), "u0", { roomId, roundKey });
    return { roomId, uids, winner, rival, others: uids.filter((u) => u !== winner && u !== rival) };
  }

  it("offers a vote to the tied players and keeps shared titles if anyone declines", async () => {
    const { roomId, winner, rival, others } = await tiedGame();
    const r = await room(roomId);
    expect(r.status).toBe("tiebreakVote");
    expect(r.tiebreak!.title).toBe("King");
    expect(r.tiebreak!.uids.slice().sort()).toEqual([winner, rival].sort());
    expect(r.final!.filter((s) => s.title === "King")).toHaveLength(2);

    await expectCode(ops.tiebreakVote(deps(), others[0], { roomId, accept: true }), "permission-denied");
    expect((await ops.tiebreakVote(deps(), winner, { roomId, accept: true })).outcome).toBe("waiting");
    expect((await ops.tiebreakVote(deps(), rival, { roomId, accept: false })).outcome).toBe("declined");
    const done = await room(roomId);
    expect(done.status).toBe("finished");
    expect(done.tiebreak!.stage).toBe("declined");
    expect(done.final!.filter((s) => s.title === "King")).toHaveLength(2);
    expect(done.final!.filter((s) => s.rank === 1)).toHaveLength(2);
  });

  it("runs an extra round among only the tied players when all accept", async () => {
    const { roomId, winner, rival, others } = await tiedGame();
    const before = await room(roomId);
    const otherHand = await hand(roomId, others[0]);
    await ops.tiebreakVote(deps(), winner, { roomId, accept: true });
    const started = await ops.tiebreakVote(deps(), rival, { roomId, accept: true });
    expect(started.outcome).toBe("started");

    const r = await room(roomId);
    expect(r.status).toBe("playing");
    expect(r.tiebreak!.stage).toBe("playing");
    const key = r.currentRoundKey!;
    const tbRound = await round(roomId, key);
    expect(tbRound.tiebreak).toBe(true);
    expect(tbRound.order.slice().sort()).toEqual([winner, rival].sort());
    expect(tbRound.movieNames).toHaveLength(2);
    expect(tbRound.chits).toHaveLength(8);
    await expectCode(
      ops.pickChit(deps(), others[0], { roomId, roundKey: key, chitId: tbRound.chits[0] }),
      "permission-denied",
    );
    await pickAll(roomId, key);
    expect((await hand(roomId, winner)).cards).toHaveLength(4);
    // Spectators keep their old (revealed) hand; they are not dealt in.
    expect((await hand(roomId, others[0])).roundKey).toBe(otherHand.roundKey);
    await expectCode(ops.nextRound(deps(), "u0", { roomId }), "failed-precondition");

    clock += 6000;
    const won = await playUntilWin(roomId, key);
    const picked = await pickChars(roomId, key);
    clock = picked.revealAt!.toMillis() + 1;
    await ops.revealRound(deps(), others[0], { roomId, roundKey: key }); // a spectator may trigger it

    const done = await room(roomId);
    expect(done.status).toBe("finished");
    expect(done.tiebreak!.stage).toBe("done");
    expect(done.totals).toEqual(before.totals); // tie-breaker points never reach totals
    expect(done.movieWins).toEqual(before.movieWins);
    const tbWinner = won.winner!.uid;
    expect(done.tiebreakScores![tbWinner]).toBe(1000);
    const kings = done.final!.filter((s) => s.title === "King");
    expect(kings.map((k) => k.uid)).toEqual([tbWinner]);
    expect(done.final!.find((s) => s.title === "Queen")!.uid).toBe(tbWinner === winner ? rival : winner);
    // Not offered a second time.
    expect(done.final!.filter((s) => s.rank === 1)).toHaveLength(1);
  });

  it("closes the vote after the deadline; silence counts as no", async () => {
    const { roomId, others } = await tiedGame();
    await expectCode(ops.resolveTiebreakVote(deps(), others[0], { roomId }), "failed-precondition");
    clock += 31_000;
    await expectCode(
      ops.tiebreakVote(deps(), (await room(roomId)).tiebreak!.uids[0], { roomId, accept: true }),
      "failed-precondition",
    );
    expect((await ops.resolveTiebreakVote(deps(), others[0], { roomId })).outcome).toBe("declined");
    expect((await room(roomId)).status).toBe("finished");
  });

  it("a tied player leaving cancels the tie-breaker and keeps shared titles", async () => {
    const { roomId, rival } = await tiedGame();
    await ops.leaveRoom(deps(), rival, { roomId });
    const r = await room(roomId);
    expect(r.status).toBe("finished");
    expect(r.tiebreak!.stage).toBe("cancelled");
  });
});

describe("picking folded chits", () => {
  async function picking(n = 4) {
    const l = await lobby(n);
    const { roundKey } = await ops.startGame(deps(), "u0", { roomId: l.roomId });
    return { ...l, roundKey, r: await round(l.roomId, roundKey) };
  }

  it("starts with empty hands, opaque chits on the table and no secrets in public", async () => {
    const { roomId, roundKey, r, uids } = await picking();
    expect(r.status).toBe("picking");
    expect(r.chits).toHaveLength(16);
    expect(new Set(r.chits).size).toBe(16);
    for (const u of uids) expect((await hand(roomId, u)).cards).toEqual([]);
    expect(JSON.stringify(r)).not.toMatch(/"name"|"cards"/);
    await expectCode(ops.pickChit(deps(), "u1", { roomId, roundKey, chitId: r.chits[0] }), "failed-precondition");
  });

  it("binds each pick to the player's fair hand; the result obeys the deal rules", async () => {
    for (let trial = 0; trial < 3; trial++) {
      const { roomId, roundKey, uids } = await picking();
      const done = await pickAll(roomId, roundKey);
      expect(done.status).toBe("exchange");
      expect(Object.keys(done.picks)).toHaveLength(16);
      const all: Card[] = [];
      for (const u of uids) {
        const h = await hand(roomId, u);
        expect(h.cards).toHaveLength(4);
        expect(new Set(h.cards.map((c) => c.name)).size).toBe(4);
        all.push(...h.cards);
      }
      expect(new Set(all.map((c) => c.id)).size).toBe(16);
      expect(done.introEndsAt.toMillis()).toBeGreaterThan(clock);
    }
  });

  it("prevents duplicate picks, foreign picks, extra picks and unknown chits", async () => {
    const { roomId, roundKey, r } = await picking();
    clock = r.pickOpensAt.toMillis() + 1;
    const [a, b, c, d, e, f] = r.chits;
    const first = await ops.pickChit(deps(), "u1", { roomId, roundKey, chitId: a });
    expect(first.card).toBeTruthy();
    // Retried request: same slip back, nothing changes.
    const retry = await ops.pickChit(deps(), "u1", { roomId, roundKey, chitId: a });
    expect(retry.duplicate).toBe(true);
    expect(retry.card).toEqual(first.card);
    expect((await hand(roomId, "u1")).cards).toHaveLength(1);
    await expectCode(ops.pickChit(deps(), "u2", { roomId, roundKey, chitId: a }), "already-exists");
    await expectCode(ops.pickChit(deps(), "outsider", { roomId, roundKey, chitId: b }), "permission-denied");
    await expectCode(ops.pickChit(deps(), "u1", { roomId, roundKey, chitId: "nope" }), "invalid-argument");
    for (const chit of [b, c, d]) await ops.pickChit(deps(), "u1", { roomId, roundKey, chitId: chit });
    await expectCode(ops.pickChit(deps(), "u1", { roomId, roundKey, chitId: e }), "failed-precondition");
    expect((await hand(roomId, "u1")).cards).toHaveLength(4);
    expect((await round(roomId, roundKey)).picks[f]).toBeUndefined();
  });

  it("when everyone grabs the same chit at once, exactly one gets it", async () => {
    const { roomId, roundKey, r, uids } = await picking();
    clock = r.pickOpensAt.toMillis() + 1;
    const results = await Promise.allSettled(
      uids.map((u) => ops.pickChit(deps(), u, { roomId, roundKey, chitId: r.chits[5] })),
    );
    expect(results.filter((x) => x.status === "fulfilled")).toHaveLength(1);
    const owners = await Promise.all(uids.map(async (u) => (await hand(roomId, u)).cards.length));
    expect(owners.reduce((a, b) => a + b, 0)).toBe(1);
  });

  it("auto-picks for slow players only after the deadline", async () => {
    const { roomId, roundKey, r, uids } = await picking();
    clock = r.pickOpensAt.toMillis() + 1;
    await ops.pickChit(deps(), "u2", { roomId, roundKey, chitId: r.chits[0] });
    await expectCode(ops.autoPickChits(deps(), "u0", { roomId, roundKey }), "failed-precondition");
    clock = r.pickDeadline.toMillis() + 1500;
    expect((await ops.autoPickChits(deps(), "u0", { roomId, roundKey })).assigned).toBe(15);
    const done = await round(roomId, roundKey);
    expect(done.status).toBe("exchange");
    for (const u of uids) {
      const h = await hand(roomId, u);
      expect(new Set(h.cards.map((c) => c.name)).size).toBe(4);
    }
  });

  it("character chits: one per non-winner, private until the reveal, no double picks", async () => {
    const { roomId, roundKey, uids } = await picking();
    await pickAll(roomId, roundKey);
    clock += 6000;
    const won = await playUntilWin(roomId, roundKey);
    const winner = won.winner!.uid;
    const others = uids.filter((u) => u !== winner);
    expect(won.charChits).toHaveLength(3);
    expect(JSON.stringify(won)).not.toMatch(/Queen|Police|Thief/);
    await expectCode(
      ops.pickCharacter(deps(), others[0], { roomId, roundKey, chitId: won.charChits[0] }),
      "failed-precondition",
    ); // still folding
    clock = won.charPickOpensAt!.toMillis() + 1;
    await expectCode(
      ops.pickCharacter(deps(), winner, { roomId, roundKey, chitId: won.charChits[0] }),
      "permission-denied",
    );
    const mine = await ops.pickCharacter(deps(), others[0], { roomId, roundKey, chitId: won.charChits[0] });
    expect(["Queen", "Police", "Thief"]).toContain(mine.character!.name);
    expect((await hand(roomId, others[0])).character).toEqual(mine.character);
    await expectCode(
      ops.pickCharacter(deps(), others[0], { roomId, roundKey, chitId: won.charChits[1] }),
      "failed-precondition",
    );
    await expectCode(
      ops.pickCharacter(deps(), others[1], { roomId, roundKey, chitId: won.charChits[0] }),
      "already-exists",
    );
    // No reveal until everyone has a character.
    await expectCode(ops.revealRound(deps(), "u0", { roomId, roundKey }), "failed-precondition");
    await expectCode(ops.autoPickCharacters(deps(), "u0", { roomId, roundKey }), "failed-precondition");
    clock = won.charPickDeadline!.toMillis() + 1500;
    expect((await ops.autoPickCharacters(deps(), "u0", { roomId, roundKey })).assigned).toBe(2);
    const after = await round(roomId, roundKey);
    expect(after.revealAt).not.toBeNull();
    const names = await Promise.all(others.map(async (u) => (await hand(roomId, u)).character!.name));
    expect(names.sort()).toEqual(["Police", "Queen", "Thief"]);
    expect((await hand(roomId, winner)).character).toBeNull();
    clock = after.revealAt!.toMillis() + 1;
    await ops.revealRound(deps(), "u1", { roomId, roundKey });
    const revealed = await round(roomId, roundKey);
    expect(revealed.scores![winner]).toBe(1000);
    expect(Object.values(revealed.scores!).reduce((a, b) => a + b, 0)).toBe(2400);
  });

  it("leaving while chits are being picked voids the round", async () => {
    const { roomId, roundKey } = await picking();
    await ops.leaveRoom(deps(), "u2", { roomId });
    expect((await round(roomId, roundKey)).status).toBe("aborted");
  });
});

