import { randomInt } from "crypto";
import { Rng } from "./types";

/** Cryptographically secure RNG used in production. */
export const secureRng: Rng = (maxExclusive) => randomInt(maxExclusive);

/** Deterministic RNG for tests (mulberry32). */
export function seededRng(seed: number): Rng {
  let a = seed >>> 0;
  return (maxExclusive) => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    const r = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    return Math.floor(r * maxExclusive);
  };
}

/** Unbiased Fisher–Yates shuffle; returns a new array. */
export function shuffle<T>(items: readonly T[], rng: Rng): T[] {
  const out = items.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = rng(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

const ID_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";

export function randomId(rng: Rng, length = 10): string {
  let s = "";
  for (let i = 0; i < length; i++) s += ID_ALPHABET[rng(ID_ALPHABET.length)];
  return s;
}

/** Room codes avoid look-alike characters (0/O, 1/I/L). */
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function roomCode(rng: Rng, length = 6): string {
  let s = "";
  for (let i = 0; i < length; i++) s += CODE_ALPHABET[rng(CODE_ALPHABET.length)];
  return s;
}
