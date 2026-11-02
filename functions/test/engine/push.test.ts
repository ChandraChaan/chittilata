import { describe, expect, it } from "vitest";
import { kqPushes, nudgePush, roomPushes, roundPushes } from "../../src/game/push";
import type { RoomDoc, RoundDoc } from "../../src/game/model";
import type { KqRoundDoc } from "../../src/game/kq";

const names: Record<string, string> = { a: "Asha", b: "Bala", c: "Chitti" };
const name = (u: string) => names[u] ?? "Someone";

const round = (o: Partial<RoundDoc>): RoundDoc =>
  ({
    roundNo: 2,
    tiebreak: false,
    status: "picking",
    order: ["a", "b", "c"],
    currentUid: "a",
    nextUid: "b",
    lastAction: null,
    winner: null,
    ...o,
  }) as RoundDoc;

describe("movie round pushes", () => {
  it("a new round tells everyone to pick", () => {
    const p = roundPushes(undefined, round({}), name);
    expect(p.map((x) => x.uid)).toEqual(["a", "b", "c"]);
    expect(p[0].title).toContain("Round 2");
  });

  it("only the player whose turn it now is gets told, with who passed", () => {
    const before = round({ status: "exchange", currentUid: "a", nextUid: "b" });
    const after = round({
      status: "exchange",
      currentUid: "b",
      nextUid: "c",
      lastAction: { type: "pass", fromUid: "a", toUid: "b" } as RoundDoc["lastAction"],
    });
    const p = roundPushes(before, after, name);
    expect(p).toHaveLength(1);
    expect(p[0].uid).toBe("b");
    expect(p[0].body).toBe("Asha passed you a chit. Pass one on to Chitti.");
  });

  it("passing starting tells the first passer", () => {
    const p = roundPushes(round({ status: "picking" }), round({ status: "exchange" }), name);
    expect(p).toEqual([expect.objectContaining({ uid: "a", body: "You pass first. Pass a chit to Bala." })]);
  });

  it("no push when the turn didn't move", () => {
    const r = round({ status: "exchange" });
    expect(roundPushes(r, { ...r }, name)).toEqual([]);
  });

  it("character picking tells everyone except the winner", () => {
    const after = round({ status: "characters", winner: { uid: "c" } as RoundDoc["winner"] });
    const p = roundPushes(round({ status: "exchange" }), after, name);
    expect(p.map((x) => x.uid)).toEqual(["a", "b"]);
    expect(p[0].title).toContain("Chitti");
  });

  it("never mentions card names", () => {
    const after = round({ status: "characters", winner: { uid: "c", movie: "RRR" } as RoundDoc["winner"] });
    for (const p of roundPushes(round({ status: "exchange" }), after, name)) {
      expect(`${p.title} ${p.body}`).not.toContain("RRR");
    }
  });
});

describe("King & Queen pushes", () => {
  const kq = (o: Partial<KqRoundDoc>): KqRoundDoc =>
    ({ roundNo: 1, status: "picking", players: ["a", "b", "c", "d"], guesser: null, step: 0, chain: ["King", "Queen", "Police", "Thief"], ...o }) as KqRoundDoc;

  it("a new round tells everyone to pick a role", () => {
    expect(kqPushes(undefined, kq({})).map((p) => p.uid)).toEqual(["a", "b", "c", "d"]);
  });

  it("the new guesser is told which role to find", () => {
    const p = kqPushes(kq({ status: "guessing", guesser: "a" }), kq({ status: "guessing", guesser: "b", step: 1 }));
    expect(p).toEqual([expect.objectContaining({ uid: "b", body: expect.stringContaining("Police") })]);
  });
});

describe("room and nudge pushes", () => {
  it("a tie-breaker vote calls the tied players", () => {
    const after = { status: "tiebreakVote", tiebreak: { title: "King", uids: ["a", "b"] } } as unknown as RoomDoc;
    const p = roomPushes({ status: "playing" } as RoomDoc, after);
    expect(p.map((x) => x.uid)).toEqual(["a", "b"]);
  });

  it("a nudge reaches its target only", () => {
    expect(nudgePush({ kind: "nudge", to: "b" }, "a", name)).toEqual([
      expect.objectContaining({ uid: "b", title: "👋 Asha nudged you" }),
    ]);
    expect(nudgePush({ kind: "emoji", to: null }, "a", name)).toEqual([]);
    expect(nudgePush({ kind: "nudge", to: "a" }, "a", name)).toEqual([]);
  });
});
