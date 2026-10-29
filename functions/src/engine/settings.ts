import { eligibleNames } from "./catalogue";
import { charactersFor, DEFAULT_CHARACTERS } from "./characters";
import {
  Category,
  CharacterDef,
  Difficulty,
  GameError,
  GameSettings,
  MAX_PLAYERS,
  MIN_PLAYERS,
  TimeoutPolicy,
} from "./types";

export const TURN_SECONDS_OPTIONS = [0, 10, 15, 20, 30, 45, 60];
export const DIFFICULTY_TURN_SECONDS: Record<Difficulty, number> = {
  easy: 30,
  normal: 20,
  challenging: 10,
};
export const MAX_ROUNDS = 30;
export const MAX_CUSTOM_NAMES = 60;
export const MAX_CHARACTERS = MAX_PLAYERS - 1;

const CATEGORIES: Category[] = ["telugu", "indian", "hollywood", "custom", "mixed"];
const DIFFICULTIES: Difficulty[] = ["easy", "normal", "challenging"];
const POLICIES: TimeoutPolicy[] = ["passIncoming", "passRandom"];

export function defaultSettings(): GameSettings {
  return {
    category: "telugu",
    customNames: [],
    rounds: 7,
    turnSeconds: DIFFICULTY_TURN_SECONDS.normal,
    difficulty: "normal",
    timeoutPolicy: "passIncoming",
    winPoints: 1000,
    characters: DEFAULT_CHARACTERS.map((c) => ({ ...c })),
  };
}

const bad = (msg: string): never => {
  throw new GameError("invalid-argument", msg);
};

function cleanText(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") bad(`${field} must be text.`);
  const s = (value as string).replace(/\s+/g, " ").trim();
  if (!s) bad(`${field} cannot be empty.`);
  if (s.length > max) bad(`${field} must be at most ${max} characters.`);
  return s;
}

function intIn(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value)) bad(`${field} must be a whole number.`);
  const n = value as number;
  if (n < min || n > max) bad(`${field} must be between ${min} and ${max}.`);
  return n;
}

export function cleanPlayerName(value: unknown): string {
  return cleanText(value, "Name", 16);
}

/** Merges a partial update over current settings, validating every field. */
export function mergeSettings(current: GameSettings, patch: unknown): GameSettings {
  if (typeof patch !== "object" || patch === null || Array.isArray(patch)) {
    bad("Settings must be an object.");
  }
  const p = patch as Record<string, unknown>;
  const next: GameSettings = { ...current };

  if ("category" in p) {
    if (!CATEGORIES.includes(p.category as Category)) bad("Unknown category.");
    next.category = p.category as Category;
  }
  if ("difficulty" in p) {
    if (!DIFFICULTIES.includes(p.difficulty as Difficulty)) bad("Unknown difficulty.");
    next.difficulty = p.difficulty as Difficulty;
  }
  if ("timeoutPolicy" in p) {
    if (!POLICIES.includes(p.timeoutPolicy as TimeoutPolicy)) bad("Unknown timeout policy.");
    next.timeoutPolicy = p.timeoutPolicy as TimeoutPolicy;
  }
  if ("rounds" in p) next.rounds = intIn(p.rounds, "Rounds", 1, MAX_ROUNDS);
  if ("turnSeconds" in p) {
    if (!TURN_SECONDS_OPTIONS.includes(p.turnSeconds as number)) bad("Unsupported turn timer.");
    next.turnSeconds = p.turnSeconds as number;
  }
  if ("winPoints" in p) next.winPoints = intIn(p.winPoints, "Win points", 100, 5000);
  if ("customNames" in p) {
    if (!Array.isArray(p.customNames)) bad("Custom names must be a list.");
    const names = (p.customNames as unknown[]).map((n) => cleanText(n, "Custom name", 24));
    if (names.length > MAX_CUSTOM_NAMES) bad(`At most ${MAX_CUSTOM_NAMES} custom names.`);
    next.customNames = names;
  }
  if ("characters" in p) {
    if (!Array.isArray(p.characters)) bad("Characters must be a list.");
    const list = p.characters as unknown[];
    if (list.length < MIN_PLAYERS - 1 || list.length > MAX_CHARACTERS) {
      bad(`Provide between ${MIN_PLAYERS - 1} and ${MAX_CHARACTERS} characters.`);
    }
    const chars: CharacterDef[] = list.map((c) => {
      const o = (c ?? {}) as Record<string, unknown>;
      return {
        name: cleanText(o.name, "Character name", 16),
        points: intIn(o.points, "Character points", 0, 5000),
      };
    });
    const keys = new Set(chars.map((c) => c.name.toLowerCase()));
    if (keys.size !== chars.length) bad("Character names must be different.");
    next.characters = chars;
  }
  return next;
}

/** Checks the settings can actually run a game with this many players. */
export function validateForStart(settings: GameSettings, playerCount: number): void {
  if (playerCount < MIN_PLAYERS || playerCount > MAX_PLAYERS) {
    throw new GameError(
      "failed-precondition",
      `Chittilata needs ${MIN_PLAYERS}-${MAX_PLAYERS} players (you have ${playerCount}).`,
    );
  }
  charactersFor(settings.characters, playerCount - 1);
  const pool = eligibleNames(settings.category, settings.difficulty, settings.customNames);
  if (pool.length < playerCount) {
    throw new GameError(
      "failed-precondition",
      `This category needs at least ${playerCount} different names; it has ${pool.length}.`,
    );
  }
}
