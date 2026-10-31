import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { resolve } from "path";
import { doc, getDoc, serverTimestamp, setDoc, updateDoc, deleteDoc, Timestamp } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;
const ROOM = "room1";

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-chittilata-rules",
    firestore: { rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8") },
  });
});

afterAll(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "roomCodes/ABC234"), { roomId: ROOM });
    await setDoc(doc(db, `rooms/${ROOM}`), {
      code: "ABC234",
      hostUid: "host",
      status: "playing",
      memberUids: ["host", "alice", "bob"],
      totals: { host: 0, alice: 0, bob: 0 },
    });
    await setDoc(doc(db, `rooms/${ROOM}/rounds/g1r01`), { status: "exchange", currentUid: "alice", turnId: 3 });
    for (const uid of ["host", "alice", "bob"]) {
      await setDoc(doc(db, `rooms/${ROOM}/hands/${uid}`), {
        cards: [{ id: `${uid}1`, name: "RRR" }],
        character: { name: "Queen", points: 800 },
      });
    }
    await setDoc(doc(db, `rooms/${ROOM}/audit/a1`), { type: "deal" });
    await setDoc(doc(db, `rooms/${ROOM}/secrets/g1r01`), { deal: {}, characters: { c1: { name: "Queen" } } });
    await setDoc(doc(db, `rooms/${ROOM}/kqRounds/g1r01`), { status: "guessing", guesser: "alice" });
    for (const uid of ["host", "alice", "bob"]) {
      await setDoc(doc(db, `rooms/${ROOM}/kqRoles/${uid}`), { index: 1, name: "Queen" });
    }
  });
});

const as = (uid: string | null) =>
  uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();

describe("room access", () => {
  it("members can read the room and its rounds", async () => {
    await assertSucceeds(getDoc(doc(as("alice"), `rooms/${ROOM}`)));
    await assertSucceeds(getDoc(doc(as("alice"), `rooms/${ROOM}/rounds/g1r01`)));
  });

  it("outsiders and signed-out users cannot read a room", async () => {
    await assertFails(getDoc(doc(as("mallory"), `rooms/${ROOM}`)));
    await assertFails(getDoc(doc(as("mallory"), `rooms/${ROOM}/rounds/g1r01`)));
    await assertFails(getDoc(doc(as(null), `rooms/${ROOM}`)));
  });

  it("nobody can read the room-code index", async () => {
    await assertFails(getDoc(doc(as("alice"), "roomCodes/ABC234")));
    await assertFails(getDoc(doc(as("mallory"), "roomCodes/ABC234")));
  });
});

describe("private hands", () => {
  it("a player can read only their own hand", async () => {
    await assertSucceeds(getDoc(doc(as("alice"), `rooms/${ROOM}/hands/alice`)));
    await assertFails(getDoc(doc(as("alice"), `rooms/${ROOM}/hands/bob`)));
  });

  it("the host gets no access to other players' hands", async () => {
    await assertFails(getDoc(doc(as("host"), `rooms/${ROOM}/hands/alice`)));
  });

  it("nobody can write a hand, even their own", async () => {
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/hands/alice`), { cards: [] }));
    await assertFails(updateDoc(doc(as("alice"), `rooms/${ROOM}/hands/alice`), { character: null }));
    await assertFails(deleteDoc(doc(as("alice"), `rooms/${ROOM}/hands/bob`)));
  });

  it("the audit log is unreadable", async () => {
    await assertFails(getDoc(doc(as("host"), `rooms/${ROOM}/audit/a1`)));
  });

  it("undealt slips and sealed character chits are unreadable by everyone", async () => {
    for (const u of ["host", "alice", "bob"]) {
      await assertFails(getDoc(doc(as(u), `rooms/${ROOM}/secrets/g1r01`)));
      await assertFails(setDoc(doc(as(u), `rooms/${ROOM}/secrets/g1r01`), { deal: {} }));
    }
  });
});

describe("King & Queen privacy", () => {
  it("members read the public round; outsiders cannot", async () => {
    await assertSucceeds(getDoc(doc(as("bob"), `rooms/${ROOM}/kqRounds/g1r01`)));
    await assertFails(getDoc(doc(as("mallory"), `rooms/${ROOM}/kqRounds/g1r01`)));
  });

  it("a secret role is readable only by its owner, never the host", async () => {
    await assertSucceeds(getDoc(doc(as("alice"), `rooms/${ROOM}/kqRoles/alice`)));
    await assertFails(getDoc(doc(as("alice"), `rooms/${ROOM}/kqRoles/bob`)));
    await assertFails(getDoc(doc(as("host"), `rooms/${ROOM}/kqRoles/alice`)));
    await assertFails(getDoc(doc(as("mallory"), `rooms/${ROOM}/kqRoles/mallory`)));
  });

  it("clients cannot change roles, guesses or turns", async () => {
    await assertFails(updateDoc(doc(as("alice"), `rooms/${ROOM}/kqRoles/alice`), { index: 0, name: "King" }));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/kqRoles/bob`), { index: 3 }));
    await assertFails(updateDoc(doc(as("alice"), `rooms/${ROOM}/kqRounds/g1r01`), { guesser: "bob" }));
    await assertFails(updateDoc(doc(as("host"), `rooms/${ROOM}/kqRounds/g1r01`), { status: "revealed" }));
  });
});

describe("game state is server-only", () => {
  it("players cannot change scores, order, status or turn", async () => {
    const db = as("alice");
    await assertFails(updateDoc(doc(db, `rooms/${ROOM}`), { "totals.alice": 99999 }));
    await assertFails(updateDoc(doc(db, `rooms/${ROOM}`), { hostUid: "alice" }));
    await assertFails(updateDoc(doc(db, `rooms/${ROOM}`), { memberUids: ["alice"] }));
    await assertFails(updateDoc(doc(db, `rooms/${ROOM}/rounds/g1r01`), { currentUid: "bob" }));
    await assertFails(updateDoc(doc(db, `rooms/${ROOM}/rounds/g1r01`), { winner: { uid: "alice" } }));
    await assertFails(setDoc(doc(db, `rooms/${ROOM}/rounds/g1r02`), { status: "exchange" }));
  });

  it("the host cannot write game state either", async () => {
    await assertFails(updateDoc(doc(as("host"), `rooms/${ROOM}`), { status: "finished" }));
  });

  it("nobody can create rooms or codes directly", async () => {
    await assertFails(setDoc(doc(as("alice"), "rooms/fake"), { memberUids: ["alice"] }));
    await assertFails(setDoc(doc(as("alice"), "roomCodes/ZZZZZZ"), { roomId: "fake" }));
  });
});

describe("presence", () => {
  it("a member can write their own heartbeat with server time", async () => {
    await assertSucceeds(
      setDoc(doc(as("alice"), `rooms/${ROOM}/presence/alice`), { lastSeen: serverTimestamp(), state: "foreground" }),
    );
    await assertSucceeds(getDoc(doc(as("bob"), `rooms/${ROOM}/presence/alice`)));
  });

  it("cannot impersonate, fake the time, add fields, or join by writing presence", async () => {
    await assertFails(
      setDoc(doc(as("alice"), `rooms/${ROOM}/presence/bob`), { lastSeen: serverTimestamp(), state: "foreground" }),
    );
    await assertFails(
      setDoc(doc(as("alice"), `rooms/${ROOM}/presence/alice`), {
        lastSeen: Timestamp.fromMillis(Date.now() + 1e9),
        state: "foreground",
      }),
    );
    await assertFails(
      setDoc(doc(as("alice"), `rooms/${ROOM}/presence/alice`), {
        lastSeen: serverTimestamp(),
        state: "foreground",
        score: 1,
      }),
    );
    await assertFails(
      setDoc(doc(as("mallory"), `rooms/${ROOM}/presence/mallory`), { lastSeen: serverTimestamp(), state: "foreground" }),
    );
  });
});

describe("quick chat", () => {
  const msg = (extra: Record<string, unknown> = {}) => ({
    id: "k3x9a",
    kind: "emoji",
    code: "laugh",
    to: null,
    at: serverTimestamp(),
    ...extra,
  });

  it("a member can send a preset emoji, phrase or nudge that the room can read", async () => {
    await assertSucceeds(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg()));
    await assertSucceeds(getDoc(doc(as("bob"), `rooms/${ROOM}/chat/alice`)));
    await assertSucceeds(setDoc(doc(as("bob"), `rooms/${ROOM}/chat/bob`), msg({ kind: "phrase", code: "hurry" })));
    await assertSucceeds(setDoc(doc(as("host"), `rooms/${ROOM}/chat/host`), msg({ kind: "nudge", code: "nudge", to: "alice" })));
    await assertFails(getDoc(doc(as("mallory"), `rooms/${ROOM}/chat/alice`)));
  });

  it("rejects free text, fake times, impersonation, outsiders and unknown targets", async () => {
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg({ code: "Hello there!" })));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg({ text: "hi" })));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg({ id: "Hello there" })));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg({ kind: "message" })));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg({ at: Timestamp.fromMillis(1) })));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/bob`), msg()));
    await assertFails(setDoc(doc(as("mallory"), `rooms/${ROOM}/chat/mallory`), msg()));
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg({ kind: "nudge", to: "mallory" })));
    await assertFails(deleteDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`)));
  });

  it("allows at most one message per second per player", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `rooms/${ROOM}/chat/alice`), { id: "a1", kind: "emoji", code: "fire", to: null, at: Timestamp.now() });
      await setDoc(doc(ctx.firestore(), `rooms/${ROOM}/chat/bob`), {
        id: "b1",
        kind: "emoji",
        code: "fire",
        to: null,
        at: Timestamp.fromMillis(Date.now() - 5000),
      });
    });
    await assertFails(setDoc(doc(as("alice"), `rooms/${ROOM}/chat/alice`), msg()));
    await assertSucceeds(setDoc(doc(as("bob"), `rooms/${ROOM}/chat/bob`), msg()));
  });
});
