#!/usr/bin/env node
/**
 * Bot players for testing Chittilata with real clients against the deployed
 * (or emulated) backend. Bots use the same callables and security rules as
 * the app, so they can only see their own hand.
 *
 *   Join an existing room:   node scripts/bots.mjs --code ABC234 --count 3
 *   Host a full bot game:    node scripts/bots.mjs --create --count 4 --rounds 2
 *   Against emulators:       add --emulator
 *   Force a Queen tie:       --create --rounds 1 --force-tie   (Queen and Police both worth 500)
 *   Tie-breaker vote:        --tiebreak accept|decline (default accept)
 *   King & Queen mode:       --create --mode kq --count 4 --rounds 2
 *
 * The Firebase web config below is a public client identifier, not a secret.
 */
import { initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import {
  connectFirestoreEmulator,
  doc,
  getFirestore,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";

const config = {
  apiKey: "AIzaSyAqDOkRHoBltek9PnNJ13feWIOy8X96CMk",
  authDomain: "chittilata-game.firebaseapp.com",
  projectId: "chittilata-game",
  appId: "1:158543185837:web:4c0ab9efab5850dde50324",
};

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};

const COUNT = Number(opt("count", 3));
const DELAY = Number(opt("delay", 1800));
const ROUNDS = Number(opt("rounds", 2));
/** Extra ms before each chit pick, so a human can pick first in demos. */
const PICK_DELAY = Number(opt("pick-delay", 600));
const NAMES = ["Vasavi", "Swetha", "Sai", "Ravi", "Lata", "Kiran", "Anu", "Meena", "Gopi"];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (who, ...m) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${who}:`, ...m);

function makeClient(i) {
  const app = initializeApp(config, `bot${i}`);
  const auth = getAuth(app);
  const db = getFirestore(app);
  const fns = getFunctions(app, "asia-south1");
  if (flag("emulator")) {
    connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
    connectFirestoreEmulator(db, "127.0.0.1", 8080);
    connectFunctionsEmulator(fns, "127.0.0.1", 5001);
  }
  const call = async (name, data) => (await httpsCallable(fns, name)(data)).data;
  return { auth, db, call };
}

/** Pass a slip of the name we hold fewest of (keeps building a set). */
function chooseCard(cards) {
  const counts = {};
  for (const c of cards) counts[c.name] = (counts[c.name] ?? 0) + 1;
  return [...cards].sort((a, b) => counts[a.name] - counts[b.name] || (Math.random() - 0.5))[0];
}

async function runBot(i, { code, roomId: knownRoomId, host }) {
  const name = host ? opt("host-name", "HostBot") : NAMES[i % NAMES.length];
  const { auth, db, call } = makeClient(i);
  const { user } = await signInAnonymously(auth);
  const uid = user.uid;

  let roomId = knownRoomId;
  if (host) {
    const r = await call("createRoom", { name });
    roomId = r.roomId;
    code = r.code;
    const settings = { rounds: ROUNDS, turnSeconds: 15 };
    if (flag("force-tie")) {
      settings.characters = [
        { name: "Queen", points: 500 },
        { name: "Police", points: 500 },
        { name: "Thief", points: 100 },
        { name: "Minister", points: 700 },
      ];
    }
    await call("updateSettings", { roomId, settings });
    log(name, `created room ${code}`);
  } else {
    roomId = (await call("joinRoom", { code, name })).roomId;
    await call("setReady", { roomId, ready: true });
    log(name, `joined ${code} and is ready`);
  }

  // Presence heartbeat, exactly as the app writes it.
  const beat = () =>
    setDoc(doc(db, `rooms/${roomId}/presence/${uid}`), {
      lastSeen: serverTimestamp(),
      state: "foreground",
    }).catch(() => {});
  beat();
  setInterval(beat, 20000).unref();

  let hand = null;
  let round = null;
  let room = null;
  let acting = null;
  let handUnsub = null;
  let roundUnsub = null;
  let watchingKey = null;
  const revealed = new Set();
  const advanced = new Set();
  const actedTurns = new Set();

  handUnsub = onSnapshot(doc(db, `rooms/${roomId}/hands/${uid}`), (s) => {
    hand = s.data() ?? null;
    tick();
  });

  const done = new Promise((resolve) => {
    onSnapshot(doc(db, `rooms/${roomId}`), (s) => {
      room = s.data();
      if (!room) return;
      if (room.status === "tiebreakVote" && room.tiebreak?.uids.includes(uid) && !advanced.has("vote")) {
        advanced.add("vote");
        const accept = opt("tiebreak", "accept") === "accept";
        log(name, `tied for ${room.tiebreak.title}; voting ${accept ? "for" : "against"} a tie-breaker`);
        setTimeout(() => call("tiebreakVote", { roomId, accept }).catch((e) => log(name, `vote: ${e.message}`)), 1500 + i * 700);
      }
      if (room.status === "finished" && !advanced.has("final")) {
        advanced.add("final");
        const title = (t) => room.final.filter((p) => p.title === t).map((p) => `${p.name} ${p.total}${p.tiebreak !== undefined ? ` (TB ${p.tiebreak})` : ""}`);
        log(name, `game finished (tie-breaker: ${room.tiebreak?.stage ?? "none"}). King: ${title("King").join(" & ")}; Queen: ${title("Queen").join(" & ")}`);
        setTimeout(resolve, 1500);
      }
      if (room.currentRoundKey && room.currentRoundKey !== watchingKey) {
        watchingKey = room.currentRoundKey;
        roundUnsub?.();
        roundUnsub = onSnapshot(doc(db, `rooms/${roomId}/rounds/${watchingKey}`), (rs) => {
          round = rs.data() ?? null;
          tick();
        });
      }
      tick();
    });
  });

  async function tick() {
    if (!room || !round || acting) return;
    const key = `${round.roundKey}:${round.turnId}`;
    const free = (ids, picks) => ids.filter((c) => !picks[c]);
    // Pick folded movie chits one at a time, like a person would.
    if (
      round.status === "picking" &&
      round.order.includes(uid) &&
      hand?.roundKey === round.roundKey &&
      hand.cards.length < 4
    ) {
      acting = "pick";
      await sleep(Math.max(0, round.pickOpensAt.toMillis() - Date.now()) + PICK_DELAY + Math.random() * 1200);
      const options = free(round.chits, round.picks);
      if (options.length) {
        const chitId = options[Math.floor(Math.random() * options.length)];
        try {
          const r = await call("pickChit", { roomId, roundKey: round.roundKey, chitId });
          log(name, `picked a chit: ${r.card.name}`);
        } catch (e) {
          log(name, `pick rejected: ${e.message}`);
        }
      }
      acting = null;
      setTimeout(tick, 50);
      return;
    }
    // Pick a folded character chit if we did not win.
    if (
      round.status === "characters" &&
      !round.revealAt &&
      round.order.includes(uid) &&
      round.winner?.uid !== uid &&
      !Object.values(round.charPicks ?? {}).includes(uid)
    ) {
      acting = "char";
      await sleep(Math.max(0, round.charPickOpensAt.toMillis() - Date.now()) + PICK_DELAY + 200 + Math.random() * 1500);
      const options = free(round.charChits, round.charPicks);
      if (options.length) {
        const chitId = options[Math.floor(Math.random() * options.length)];
        try {
          const r = await call("pickCharacter", { roomId, roundKey: round.roundKey, chitId });
          log(name, `secret character: ${r.character.name} (+${r.character.points})`);
        } catch (e) {
          log(name, `character pick rejected: ${e.message}`);
        }
      }
      acting = null;
      setTimeout(tick, 400); // lost a race: look again at what is left
      return;
    }
    if (
      round.status === "exchange" &&
      round.currentUid === uid &&
      hand?.roundKey === round.roundKey &&
      !actedTurns.has(key)
    ) {
      acting = key;
      actedTurns.add(key);
      const wait = Math.max(0, round.introEndsAt.toMillis() - Date.now()) + DELAY + Math.random() * 800;
      await sleep(wait);
      const card = chooseCard(hand.cards);
      try {
        const r = await call("passCard", {
          roomId,
          roundKey: round.roundKey,
          turnId: round.turnId,
          cardId: card.id,
          requestId: `${uid}-${key}`,
        });
        if (r.duplicate) log(name, "retry was de-duplicated by the server");
        else log(name, `passed a slip${r.winner === uid ? " and WON the round!" : ""}`);
      } catch (e) {
        log(name, `pass rejected: ${e.message}`);
      }
      acting = null;
      return;
    }
    if (round.status === "characters" && round.revealAt && !revealed.has(round.roundKey)) {
      revealed.add(round.roundKey);
      await sleep(Math.max(0, round.revealAt.toMillis() - Date.now()) + 1500 + i * 400);
      await call("revealRound", { roomId, roundKey: round.roundKey }).catch(() => {});
      return;
    }
    if (host && round.status === "revealed" && room.status === "playing" && !advanced.has(round.roundKey)) {
      advanced.add(round.roundKey);
      log(name, `round ${round.roundNo} scores: ${JSON.stringify(round.scores)}`);
      // Conservation check: every slip still exists exactly once, 4 per name.
      const all = Object.values(round.revealedHands).flat();
      const perName = {};
      for (const c of all) perName[c.name] = (perName[c.name] ?? 0) + 1;
      const ok =
        all.length === 4 * round.order.length &&
        new Set(all.map((c) => c.id)).size === all.length &&
        Object.values(perName).every((n) => n === 4);
      log(name, `round ${round.roundNo} card check: ${ok ? "OK" : "FAILED"} (${all.length} slips)`);
      if (!ok) process.exitCode = 2;
      await sleep(2500);
      await call("nextRound", { roomId }).catch((e) => log(name, `nextRound: ${e.message}`));
    }
  }

  /** Resolves once `n` members are in the room and all are ready. */
  const allReady = (n) =>
    new Promise((resolve) => {
      const check = setInterval(() => {
        if (!room) return;
        const ready = room.memberUids.every((u) => u === room.hostUid || room.players[u].ready);
        if (room.memberUids.length >= n && ready) {
          clearInterval(check);
          resolve();
        }
      }, 500);
    });

  // Like the app: after a picking deadline, ask the server to finish picks.
  setInterval(() => {
    if (!round) return;
    const now = Date.now() - 1500 - i * 300;
    if (round.status === "picking" && round.pickDeadline?.toMillis() < now) {
      call("autoPickChits", { roomId, roundKey: round.roundKey }).catch(() => {});
    }
    if (round.status === "characters" && !round.revealAt && round.charPickDeadline?.toMillis() < now) {
      call("autoPickCharacters", { roomId, roundKey: round.roundKey }).catch(() => {});
    }
  }, 2000).unref();

  return { code, roomId, done, allReady, start: () => call("startGame", { roomId }) };
}

/** A King & Queen bot: picks one role chit, guesses at random on its turn. */
async function runKqBot(i, { code, host }) {
  const name = host ? opt("host-name", "HostBot") : NAMES[i % NAMES.length];
  const { auth, db, call } = makeClient(i);
  const { user } = await signInAnonymously(auth);
  const uid = user.uid;
  let roomId;
  if (host) {
    const r = await call("createRoom", { name, mode: "kingQueen" });
    roomId = r.roomId;
    code = r.code;
    await call("updateSettings", { roomId, kqSettings: { rounds: ROUNDS, turnSeconds: 15 } });
    log(name, `created King & Queen room ${code}`);
  } else {
    roomId = (await call("joinRoom", { code, name })).roomId;
    await call("setReady", { roomId, ready: true });
    log(name, `joined ${code} and is ready`);
  }
  const beat = () =>
    setDoc(doc(db, `rooms/${roomId}/presence/${uid}`), { lastSeen: serverTimestamp(), state: "foreground" }).catch(() => {});
  beat();
  setInterval(beat, 20000).unref();

  let room = null;
  let round = null;
  let acting = false;
  let watching = null;
  const advanced = new Set();
  const tick = async () => {
    if (!room || !round || acting) return;
    const key = round.roundKey;
    if (round.status === "picking" && round.players.includes(uid) && !Object.values(round.picks).includes(uid)) {
      acting = true;
      await sleep(Math.max(0, round.pickOpensAt.toMillis() - Date.now()) + PICK_DELAY + Math.random() * 1200);
      const free = round.chits.filter((c) => !round.picks[c]);
      if (free.length) {
        try {
          const r = await call("kqPickChit", { roomId, roundKey: key, chitId: free[Math.floor(Math.random() * free.length)] });
          log(name, `picked a role chit: ${r.role.name}`);
        } catch (e) {
          log(name, `pick rejected: ${e.message}`);
        }
      }
      acting = false;
      setTimeout(tick, 300);
      return;
    }
    if (round.status === "guessing" && round.guesser === uid && !advanced.has(`${key}:${round.turnId}`)) {
      advanced.add(`${key}:${round.turnId}`);
      acting = true;
      await sleep(Math.max(0, round.guessOpensAt.toMillis() - Date.now()) + DELAY + Math.random() * 800);
      const out = new Set([...Object.keys(round.locked), uid, ...round.excluded]);
      const c = round.players.filter((p) => !out.has(p));
      const target = c[Math.floor(Math.random() * c.length)];
      try {
        await call("kqGuess", { roomId, roundKey: key, turnId: round.turnId, targetUid: target, requestId: `${uid}-${key}-${round.turnId}` });
        log(name, `guessed ${room.players[target]?.name} for ${round.chain[round.step + 1]}`);
      } catch (e) {
        log(name, `guess rejected: ${e.message}`);
      }
      acting = false;
      return;
    }
    if (host && round.status === "revealed" && room.status === "playing" && !advanced.has(key)) {
      advanced.add(key);
      const roles = Object.entries(round.revealedRoles).map(([u, idx]) => `${room.players[u].name}=${round.chain[idx]}`);
      const ok = new Set(Object.values(round.revealedRoles)).size === round.players.length;
      log(name, `round ${round.roundNo}: ${roles.join(", ")} | roles once each: ${ok ? "OK" : "FAILED"} | ${round.history.length} guesses`);
      if (!ok) process.exitCode = 2;
      await sleep(2500);
      await call("nextRound", { roomId }).catch((e) => log(name, `nextRound: ${e.message}`));
    }
  };
  setInterval(() => {
    if (!round) return;
    const now = Date.now() - 1500 - i * 300;
    if (round.status === "picking" && round.pickDeadline.toMillis() < now) {
      call("kqAutoPick", { roomId, roundKey: round.roundKey }).catch(() => {});
    }
    if (round.status === "guessing" && round.turnDeadline && round.turnDeadline.toMillis() < now) {
      call("kqClaimTimeout", { roomId, roundKey: round.roundKey, turnId: round.turnId }).catch(() => {});
    }
  }, 2000).unref();

  const done = new Promise((resolve) => {
    onSnapshot(doc(db, `rooms/${roomId}`), (snap) => {
      room = snap.data();
      if (!room) return;
      if (room.status === "finished" && !advanced.has("final")) {
        advanced.add("final");
        const t = (x) => room.final.filter((p) => p.title === x).map((p) => `${p.name} ${p.total}`).join(" & ");
        log(name, `game finished. King: ${t("King")}; Queen: ${t("Queen")}`);
        setTimeout(resolve, 1500);
      }
      if (room.currentRoundKey && room.currentRoundKey !== watching) {
        watching = room.currentRoundKey;
        onSnapshot(doc(db, `rooms/${roomId}/kqRounds/${watching}`), (rs) => {
          round = rs.data() ?? null;
          tick();
        });
      }
      tick();
    });
  });
  const allReady = (n) =>
    new Promise((resolve) => {
      const check = setInterval(() => {
        if (room && room.memberUids.length >= n && room.memberUids.every((u) => u === room.hostUid || room.players[u].ready)) {
          clearInterval(check);
          resolve();
        }
      }, 500);
    });
  return { code, roomId, done, allReady, start: () => call("startGame", { roomId }) };
}

async function main() {
  if (opt("mode") === "kq") {
    if (flag("create")) {
      const host = await runKqBot(0, { host: true });
      const others = [];
      for (let i = 1; i < COUNT; i++) others.push(await runKqBot(i, { code: host.code }));
      const waitFor = Number(opt("wait-for", COUNT));
      if (waitFor > COUNT) log("HostBot", `room ${host.code}: waiting for ${waitFor - COUNT} more player(s)`);
      await host.allReady(waitFor);
      await sleep(1000);
      await host.start();
      log("HostBot", "King & Queen game started");
      await Promise.all([host.done, ...others.map((o) => o.done)]);
    } else {
      const code = opt("code").toUpperCase();
      const bots = [];
      for (let i = 0; i < COUNT; i++) bots.push(await runKqBot(i, { code }));
      await Promise.all(bots.map((b) => b.done));
    }
    process.exit(0);
  }
  if (flag("create")) {
    const host = await runBot(0, { host: true });
    const others = [];
    for (let i = 1; i < COUNT; i++) others.push(await runBot(i, { code: host.code }));
    const waitFor = Number(opt("wait-for", COUNT));
    if (waitFor > COUNT) log("HostBot", `room ${host.code}: waiting for ${waitFor - COUNT} more player(s) to join and tap Ready`);
    await host.allReady(waitFor);
    await sleep(1000);
    await host.start();
    log("HostBot", "game started");
    await Promise.all([host.done, ...others.map((o) => o.done)]);
  } else {
    const code = opt("code");
    if (!code) throw new Error("Pass --code ROOMCODE or --create");
    const bots = [];
    for (let i = 0; i < COUNT; i++) bots.push(await runBot(i, { code: code.toUpperCase() }));
    log("bots", `${COUNT} bots are in room ${code}; start the game from the app.`);
    await Promise.all(bots.map((b) => b.done));
  }
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
