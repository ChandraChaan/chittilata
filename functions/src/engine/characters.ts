import { shuffle } from "./random";
import { CharacterDef, GameError, Rng } from "./types";

/**
 * Default special characters. When fewer are needed, the first N in this list
 * are used, so 4 players (3 non-winners) get Queen, Thief and Police and
 * 3 players get Queen and Thief. Up to 9 characters cover 10 players.
 */
export const DEFAULT_CHARACTERS: CharacterDef[] = [
  { name: "Queen", points: 800 },
  { name: "Thief", points: 100 },
  { name: "Police", points: 500 },
  { name: "Minister", points: 700 },
  { name: "Commander", points: 600 },
  { name: "Merchant", points: 400 },
  { name: "Poet", points: 300 },
  { name: "Farmer", points: 200 },
  { name: "Jester", points: 150 },
];

/** Exactly `count` characters, taken in list order. Throws if too few exist. */
export function charactersFor(defs: CharacterDef[], count: number): CharacterDef[] {
  if (defs.length < count) {
    throw new GameError(
      "failed-precondition",
      `This game needs ${count} special characters but only ${defs.length} are configured.`,
    );
  }
  return defs.slice(0, count);
}

/**
 * Gives every non-winner exactly one character, uniformly at random.
 * Returns uid -> character.
 */
export function assignCharacters(
  uids: string[],
  defs: CharacterDef[],
  rng: Rng,
): Record<string, CharacterDef> {
  const cards = shuffle(charactersFor(defs, uids.length), rng);
  const out: Record<string, CharacterDef> = {};
  uids.forEach((uid, i) => {
    out[uid] = { name: cards[i].name, points: cards[i].points };
  });
  return out;
}
