import type { Firestore } from "firebase-admin/firestore";
import type { Messaging } from "firebase-admin/messaging";
import type { RoomDoc, RoundDoc } from "./model";
import type { KqRoundDoc } from "./kq";

/**
 * Push notifications bring players back when the game needs them and their
 * app isn't open: their turn, a new round to pick in, a nudge. Texts never
 * include card or role names. Tokens live in pushTokens/{uid}, written by
 * each phone and readable only by the server.
 */
export interface Push {
  uid: string;
  title: string;
  body: string;
}

/** A phone counts as "looking at the game" if it said so this recently. */
export const FOREGROUND_FRESH_MS = 25_000;

type Names = (uid: string) => string;

export function namesOf(room: Pick<RoomDoc, "players">): Names {
  return (uid) => room.players?.[uid]?.name ?? "Someone";
}

/** Movie Chits round changes. */
export function roundPushes(before: RoundDoc | undefined, after: RoundDoc, name: Names): Push[] {
  const label = after.tiebreak ? "Tie-breaker" : `Round ${after.roundNo}`;
  if (!before) {
    return after.order.map((uid) => ({
      uid,
      title: `🎬 ${label} is starting!`,
      body: "Pick your 4 folded chits from the mat.",
    }));
  }
  if (after.status === "exchange") {
    const turnMoved = before.status !== "exchange" || before.currentUid !== after.currentUid;
    if (!turnMoved) return [];
    const from = after.lastAction?.toUid === after.currentUid ? after.lastAction.fromUid : null;
    return [
      {
        uid: after.currentUid,
        title: "⏰ Your turn!",
        body: from
          ? `${name(from)} passed you a chit. Pass one on to ${name(after.nextUid)}.`
          : `You pass first. Pass a chit to ${name(after.nextUid)}.`,
      },
    ];
  }
  if (after.status === "characters" && before.status !== "characters") {
    const winner = after.winner?.uid;
    if (!winner) {
      return after.order.map((uid) => ({
        uid,
        title: "🤷 No winner this round!",
        body: "Everyone picks a character chit, King included. Go!",
      }));
    }
    return after.order
      .filter((uid) => uid !== winner)
      .map((uid) => ({
        uid,
        title: `🏆 ${name(winner)} collected four of a kind!`,
        body: "Pick a character chit before time runs out.",
      }));
  }
  return [];
}

/** The host asked a player whether they are still there. */
export function warningPushes(before: RoomDoc | undefined, after: RoomDoc): Push[] {
  const out: Push[] = [];
  for (const [uid, w] of Object.entries(after.warnings ?? {})) {
    if (!w.deadline) continue;
    const prev = before?.warnings?.[uid];
    if (prev?.deadline && prev.deadline.toMillis() === w.deadline.toMillis()) continue;
    out.push({
      uid,
      title: "⚠️ Are you still there?",
      body: `The host is waiting for you. Open the game within ${Math.round(WARNING_SECONDS_HINT)} seconds or you'll be removed.`,
    });
  }
  return out;
}

/** Shown in the warning push; kept in step with WARNING_SECONDS in model.ts. */
const WARNING_SECONDS_HINT = 60;

/** King & Queen round changes. */
export function kqPushes(before: KqRoundDoc | undefined, after: KqRoundDoc): Push[] {
  if (!before) {
    return after.players.map((uid) => ({
      uid,
      title: `👑 Round ${after.roundNo} is starting!`,
      body: "Pick your secret role chit.",
    }));
  }
  if (after.status === "guessing" && after.guesser && (before.status !== "guessing" || before.guesser !== after.guesser)) {
    const hunting = after.chain[after.step + 1] ?? "next role";
    return [
      {
        uid: after.guesser,
        title: "👑 Your turn to guess!",
        body: `Find the ${hunting}. Everyone is waiting for you.`,
      },
    ];
  }
  return [];
}

/** Room changes: a tie-breaker vote needs the tied players. */
export function roomPushes(before: RoomDoc | undefined, after: RoomDoc): Push[] {
  if (after.status === "tiebreakVote" && before?.status !== "tiebreakVote" && after.tiebreak) {
    return after.tiebreak.uids.map((uid) => ({
      uid,
      title: `🤝 Tie for ${after.tiebreak!.title}!`,
      body: "Vote now: play one more round to decide, or share the title.",
    }));
  }
  return [];
}

/** Someone nudged a player. */
export function nudgePush(chat: { kind?: string; to?: string | null } | undefined, senderUid: string, name: Names): Push[] {
  if (!chat || chat.kind !== "nudge" || !chat.to || chat.to === senderUid) return [];
  return [{ uid: chat.to, title: `👋 ${name(senderUid)} nudged you`, body: "Everyone's waiting for your move!" }];
}

/**
 * Sends [pushes] to players whose app isn't open on the game right now, and
 * forgets tokens the push service says are gone.
 */
export async function deliver(db: Firestore, messaging: Messaging, roomId: string, pushes: Push[], now: number) {
  if (pushes.length === 0) return { sent: 0 };
  const uids = [...new Set(pushes.map((p) => p.uid))];
  const room = db.collection("rooms").doc(roomId);
  const [presence, tokens] = await Promise.all([
    db.getAll(...uids.map((u) => room.collection("presence").doc(u))),
    db.getAll(...uids.map((u) => db.collection("pushTokens").doc(u))),
  ]);
  const away = new Set(
    presence
      .filter((d) => {
        const p = d.data();
        const seen = p?.lastSeen?.toMillis?.() ?? 0;
        return !(p?.state === "foreground" && now - seen < FOREGROUND_FRESH_MS);
      })
      .map((d) => d.id),
  );
  const tokenOf = new Map(tokens.filter((d) => typeof d.data()?.token === "string").map((d) => [d.id, d.data()!.token as string]));
  const messages = pushes
    .filter((p) => away.has(p.uid) && tokenOf.has(p.uid))
    .map((p) => ({
      token: tokenOf.get(p.uid)!,
      notification: { title: p.title, body: p.body },
      data: { roomId },
      android: {
        priority: "high" as const,
        // One notification per room: a newer one replaces the older.
        collapseKey: roomId,
        notification: { tag: roomId, channelId: "turns", icon: "ic_stat_chittilata", color: "#FFB627" },
      },
    }));
  if (messages.length === 0) return { sent: 0 };
  const res = await messaging.sendEach(messages);
  const dead = res.responses
    .map((r, i) => ({ r, uid: [...tokenOf.entries()].find(([, t]) => t === messages[i].token)?.[0] }))
    .filter(({ r }) => r.error?.code === "messaging/registration-token-not-registered" || r.error?.code === "messaging/invalid-registration-token")
    .map(({ uid }) => uid)
    .filter((u): u is string => !!u);
  await Promise.all(dead.map((u) => db.collection("pushTokens").doc(u).delete()));
  return { sent: res.successCount };
}
