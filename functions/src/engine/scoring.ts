export interface StandingInput {
  uid: string;
  name: string;
  total: number;
  movieWins: number;
  left?: boolean;
}

export type Title = "King" | "Queen" | null;

export interface Standing extends StandingInput {
  /** 1-based; tied players share a rank. */
  rank: number;
  title: Title;
}

/**
 * Final ranking. Tie-break rule (documented in the game rules):
 *   1. Higher total points.
 *   2. More movie-phase wins.
 *   3. Still equal: the players share the rank (and the title).
 * Everyone at rank 1 is King. Everyone at the next rank is Queen.
 * Names only order tied players for display, never decide a rank.
 */
export function rankPlayers(players: StandingInput[]): Standing[] {
  const sorted = players
    .slice()
    .sort(
      (a, b) =>
        b.total - a.total ||
        b.movieWins - a.movieWins ||
        a.name.localeCompare(b.name),
    );
  const out: Standing[] = [];
  let rank = 0;
  let distinct = 0;
  sorted.forEach((p, i) => {
    const prev = sorted[i - 1];
    if (!prev || prev.total !== p.total || prev.movieWins !== p.movieWins) {
      rank = i + 1;
      distinct++;
    }
    const title: Title = distinct === 1 ? "King" : distinct === 2 ? "Queen" : null;
    out.push({ ...p, rank, title });
  });
  return out;
}

/** Points earned in a single round: win points or the character's points. */
export function roundScores(
  playerUids: string[],
  winnerUid: string,
  winPoints: number,
  characters: Record<string, { points: number }>,
): Record<string, number> {
  const scores: Record<string, number> = {};
  for (const uid of playerUids) {
    scores[uid] = uid === winnerUid ? winPoints : (characters[uid]?.points ?? 0);
  }
  return scores;
}
