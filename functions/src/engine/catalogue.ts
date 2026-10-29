import { shuffle } from "./random";
import { Category, Difficulty, GameError, Rng } from "./types";

/**
 * Offline movie catalogue bundled with the server.
 *
 * `familiar` marks widely known blockbusters and classics; it is an editorial
 * flag used for the Easy difficulty, not a popularity ranking. There is no
 * external movie API configured, so this list is the source of truth.
 * Edit it here (and redeploy functions) to refresh the catalogue.
 */
export interface MovieEntry {
  title: string;
  year: number;
  familiar: boolean;
}

const m = (title: string, year: number, familiar = false): MovieEntry => ({
  title,
  year,
  familiar,
});

export const TELUGU_MOVIES: MovieEntry[] = [
  m("Baahubali", 2015, true),
  m("Baahubali 2", 2017, true),
  m("RRR", 2022, true),
  m("Pushpa", 2021, true),
  m("Pushpa 2", 2024, true),
  m("Salaar", 2023, true),
  m("Devara", 2024, true),
  m("Kalki 2898 AD", 2024, true),
  m("Arjun Reddy", 2017, true),
  m("Magadheera", 2009, true),
  m("Eega", 2012, true),
  m("Rangasthalam", 2018, true),
  m("Ala Vaikunthapurramuloo", 2020, true),
  m("Pokiri", 2006, true),
  m("Athadu", 2005, true),
  m("Okkadu", 2003, true),
  m("Gabbar Singh", 2012, true),
  m("Attarintiki Daredi", 2013, true),
  m("Srimanthudu", 2015, true),
  m("Mahanati", 2018, true),
  m("Sita Ramam", 2022, true),
  m("HanuMan", 2024, true),
  m("Geetha Govindam", 2018, true),
  m("Bommarillu", 2006, true),
  m("Happy Days", 2007, true),
  m("Manam", 2014, true),
  m("Jersey", 2019, true),
  m("Fidaa", 2017, true),
  m("Arya", 2004, true),
  m("Kushi", 2001, true),
  m("Indra", 2002, true),
  m("Simha", 2010, true),
  m("Dookudu", 2011, true),
  m("Businessman", 2012, true),
  m("Julayi", 2012, true),
  m("Chatrapathi", 2005, true),
  m("Vikramarkudu", 2006, true),
  m("Shiva", 1989, true),
  m("Jalsa", 2008, true),
  m("Bharat Ane Nenu", 2018),
  m("Sarileru Neekevvaru", 2020),
  m("Akhanda", 2021),
  m("Bheemla Nayak", 2022),
  m("Waltair Veerayya", 2023),
  m("Guntur Kaaram", 2024),
  m("Dasara", 2023),
  m("Baby", 2023),
  m("DJ Tillu", 2022),
  m("Tillu Square", 2024),
  m("Karthikeya 2", 2022),
  m("Major", 2022),
  m("Jathi Ratnalu", 2021),
  m("Uppena", 2021),
  m("Lucky Baskhar", 2024),
  m("Game Changer", 2025),
  m("Daaku Maharaaj", 2025),
  m("Sankranthiki Vasthunam", 2025),
  m("Court", 2025),
  m("Kubera", 2025),
  m("Mirai", 2025),
  m("They Call Him OG", 2025),
  m("Maryada Ramanna", 2010),
  m("Nuvve Kavali", 2000),
  m("Ninne Pelladatha", 1996),
  m("Tagore", 2003),
  m("Sye Raa Narasimha Reddy", 2019),
  m("Khaidi No. 150", 2017),
  m("Pelli Choopulu", 2016),
  m("Ee Nagaraniki Emaindi", 2018),
  m("Agent Sai Srinivasa Athreya", 2019),
  m("Goodachari", 2018),
  m("Bimbisara", 2022),
  m("Balagam", 2023),
  m("Hi Nanna", 2023),
  m("Saripodhaa Sanivaaram", 2024),
];

export const INDIAN_MOVIES: MovieEntry[] = [
  m("Sholay", 1975, true),
  m("Dilwale Dulhania Le Jayenge", 1995, true),
  m("3 Idiots", 2009, true),
  m("Lagaan", 2001, true),
  m("Dangal", 2016, true),
  m("PK", 2014, true),
  m("Bajrangi Bhaijaan", 2015, true),
  m("Taare Zameen Par", 2007, true),
  m("Chak De! India", 2007, true),
  m("Kabhi Khushi Kabhie Gham", 2001, true),
  m("Zindagi Na Milegi Dobara", 2011, true),
  m("Jawan", 2023, true),
  m("Pathaan", 2023, true),
  m("Animal", 2023, true),
  m("KGF Chapter 2", 2022, true),
  m("Kantara", 2022, true),
  m("Enthiran", 2010, true),
  m("Jailer", 2023, true),
  m("Vikram", 2022, true),
  m("Drishyam", 2013, true),
  m("Andhadhun", 2018),
  m("Queen", 2014),
  m("Stree", 2018),
  m("Stree 2", 2024),
  m("Gadar 2", 2023),
  m("Leo", 2023),
  m("Manjummel Boys", 2024),
  m("Premam", 2015),
  m("Kumbalangi Nights", 2019),
  m("Gangs of Wasseypur", 2012),
  m("Barfi!", 2012),
  m("Kahaani", 2012),
  m("12th Fail", 2023),
  m("Laapataa Ladies", 2024),
  m("Chhaava", 2025),
  m("Ponniyin Selvan", 2022),
  m("Super Deluxe", 2019),
  m("Asuran", 2019),
  m("Aavesham", 2024),
  m("Lucia", 2013),
  ...TELUGU_MOVIES,
];

export const HOLLYWOOD_MOVIES: MovieEntry[] = [
  m("Titanic", 1997, true),
  m("Avatar", 2009, true),
  m("Inception", 2010, true),
  m("Interstellar", 2014, true),
  m("The Dark Knight", 2008, true),
  m("Avengers: Endgame", 2019, true),
  m("Jurassic Park", 1993, true),
  m("The Lion King", 1994, true),
  m("Frozen", 2013, true),
  m("Toy Story", 1995, true),
  m("Finding Nemo", 2003, true),
  m("The Matrix", 1999, true),
  m("Forrest Gump", 1994, true),
  m("The Godfather", 1972, true),
  m("Gladiator", 2000, true),
  m("Black Panther", 2018, true),
  m("Spider-Man: No Way Home", 2021, true),
  m("Top Gun: Maverick", 2022, true),
  m("Oppenheimer", 2023, true),
  m("Barbie", 2023, true),
  m("Joker", 2019),
  m("Dune", 2021),
  m("Dune: Part Two", 2024),
  m("Inside Out 2", 2024),
  m("Deadpool & Wolverine", 2024),
  m("Wicked", 2024),
  m("Everything Everywhere All at Once", 2022),
  m("Parasite", 2019),
  m("Coco", 2017),
  m("Up", 2009),
  m("Shrek", 2001),
  m("Mad Max: Fury Road", 2015),
  m("La La Land", 2016),
  m("The Social Network", 2010),
  m("Back to the Future", 1985),
  m("Star Wars", 1977),
  m("Jaws", 1975),
  m("Moana", 2016),
  m("Encanto", 2021),
  m("A Minecraft Movie", 2025),
];

/** Presets the host can load into the Custom Names list from the app. */
export const CUSTOM_PRESETS: Record<string, string[]> = {
  countries: [
    "India", "Japan", "Brazil", "Canada", "Egypt", "France", "Kenya",
    "Mexico", "Norway", "Peru", "Spain", "Italy", "Australia", "Nepal",
  ],
  cities: [
    "Hyderabad", "Vizag", "Vijayawada", "Tirupati", "Warangal", "Chennai",
    "Bengaluru", "Mumbai", "Delhi", "Kolkata", "Pune", "Mysuru", "Guntur",
    "Nellore",
  ],
  fruits: [
    "Mango", "Banana", "Guava", "Jackfruit", "Papaya", "Grapes", "Orange",
    "Pomegranate", "Watermelon", "Pineapple", "Sapota", "Custard Apple",
  ],
};

/** Movies from this year onwards count as "recent" for Normal difficulty. */
export const RECENT_FROM_YEAR = 2015;

function moviesFor(category: Category): MovieEntry[] {
  switch (category) {
    case "telugu":
      return TELUGU_MOVIES;
    case "indian":
      return INDIAN_MOVIES;
    case "hollywood":
      return HOLLYWOOD_MOVIES;
    case "mixed":
      return [...INDIAN_MOVIES, ...HOLLYWOOD_MOVIES];
    case "custom":
      return [];
  }
}

function dedupe(names: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of names) {
    const name = raw.trim();
    const key = name.toLowerCase();
    if (!name || seen.has(key)) continue;
    seen.add(key);
    out.push(name);
  }
  return out;
}

/**
 * The names eligible for a category and difficulty.
 * Easy: familiar titles only. Normal: familiar plus recent releases.
 * Challenging: the whole category. Custom names ignore difficulty.
 */
export function eligibleNames(
  category: Category,
  difficulty: Difficulty,
  customNames: string[],
): string[] {
  if (category === "custom") return dedupe(customNames);
  const all = moviesFor(category);
  const filtered = all.filter((e) => {
    if (difficulty === "easy") return e.familiar;
    if (difficulty === "normal") return e.familiar || e.year >= RECENT_FROM_YEAR;
    return true;
  });
  return dedupe(filtered.map((e) => e.title));
}

/**
 * Picks `count` distinct names, preferring ones not yet used in this game.
 * Falls back to reusing names only when the unused pool is too small.
 */
export function pickNames(
  pool: string[],
  count: number,
  used: string[],
  rng: Rng,
): string[] {
  if (pool.length < count) {
    throw new GameError(
      "failed-precondition",
      `Need at least ${count} different names, but only ${pool.length} are available.`,
    );
  }
  const usedKeys = new Set(used.map((u) => u.toLowerCase()));
  const fresh = shuffle(
    pool.filter((n) => !usedKeys.has(n.toLowerCase())),
    rng,
  );
  if (fresh.length >= count) return fresh.slice(0, count);
  const reused = shuffle(
    pool.filter((n) => usedKeys.has(n.toLowerCase())),
    rng,
  );
  return [...fresh, ...reused.slice(0, count - fresh.length)];
}
