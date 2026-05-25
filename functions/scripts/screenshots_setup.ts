/* eslint-disable no-console */
/**
 * Screenshots-real CI helper. Two subcommands:
 *
 *   ts-node scripts/screenshots_setup.ts seed
 *     Idempotently writes a curated "screenshot test household" into the
 *     project's Firestore. Run once locally (or re-run on every CI build
 *     to keep relative timestamps fresh). Mirrors the data set in
 *     `lib/demo/demo_data.dart` so the screenshots-real APK renders the
 *     same populated household as DEMO_MODE — only over real Firebase
 *     instead of mocked Riverpod overrides.
 *
 *   ts-node scripts/screenshots_setup.ts mint-token
 *     Mints a short-lived Firebase custom token for the seeded household's
 *     viewer uid and prints it to stdout. The GHA screenshots-real workflow
 *     captures the print, bakes it into the debug APK via
 *     `--dart-define=AUTO_SIGN_IN_TOKEN=...`, and `main.dart` exchanges it
 *     for a real session at boot so the emulator skips Google Sign-In UI.
 *
 * Credentials: the script reads `FIREBASE_SERVICE_ACCOUNT_JSON` (the raw
 * JSON contents — what you'd paste into a GitHub secret) or falls back to
 * `GOOGLE_APPLICATION_CREDENTIALS` (a path to a JSON file) — same shape
 * firebase-admin honours by default for the file-path variant.
 *
 * The uid + household_id are pinned constants — re-running the seed
 * overwrites the same docs so the household never duplicates.
 */
import { cert, initializeApp, applicationDefault } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp, WriteBatch } from "firebase-admin/firestore";

// Pinned to match `lib/demo/demo_mode.dart`'s kDemoUid/kDemoPartnerUid/
// kDemoHouseholdId. Re-using these means the seeded household is
// indistinguishable from the DEMO_MODE one, which keeps the screenshots
// pipeline coherent — same uids in ratings, watchedBy, matchScoreSolo
// across both code paths. Synthetic strings like `demo_uid_alex` are
// extremely unlikely to collide with a real Google-sign-in uid (28-char
// base64-ish from Firebase Auth).
const VIEWER_UID = "demo_uid_alex";
const PARTNER_UID = "demo_uid_jamie";
const HOUSEHOLD_ID = "demo_household_1";

// ─────────────────────────────────────────────────────────────────────
// Time anchors — relative to script run time, mirroring demo_data.dart.
// Re-running the seed before every screenshot capture keeps these fresh
// so the screenshots always look like a recently-active household.
// ─────────────────────────────────────────────────────────────────────

const now = new Date();
function daysAgo(n: number): Date {
  const d = new Date(now);
  d.setDate(d.getDate() - n);
  return d;
}
function ts(d: Date): Timestamp {
  return Timestamp.fromDate(d);
}

// ─────────────────────────────────────────────────────────────────────
// Seed payloads — 1:1 mirror of lib/demo/demo_data.dart using each
// model's toFirestore field names (snake_case).
// ─────────────────────────────────────────────────────────────────────

interface RecSeed {
  id: string;
  doc: Record<string, unknown>;
}

const recommendations: RecSeed[] = [
  {
    id: "movie:496243",
    doc: {
      media_type: "movie",
      tmdb_id: 496243,
      title: "Parasite",
      year: 2019,
      poster_path: "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg",
      genres: ["Thriller", "Comedy", "Drama"],
      runtime: 132,
      match_score: 94,
      match_score_solo: { [VIEWER_UID]: 96, [PARTNER_UID]: 92 },
      ai_blurb:
        "A genre-bending thriller you both rated highly recent overlaps with — Bong's class-warfare suspense lands every beat.",
      ai_blurb_solo: {
        [VIEWER_UID]:
          "Your top-rated thriller of the last year was Anatomy of a Fall. Parasite's pivot-on-a-dime tonal shifts are in the same lane.",
      },
      source: "discover",
      scored: true,
      is_oscar_winner: true,
      imdb_id: "tt6751668",
      generated_at: ts(daysAgo(1)),
    },
  },
  {
    id: "tv:95396",
    doc: {
      media_type: "tv",
      tmdb_id: 95396,
      title: "Severance",
      year: 2022,
      poster_path: "/lFf6LLrQjYldcZItzOkGmMMigP7.jpg",
      genres: ["Sci-Fi & Fantasy", "Mystery", "Drama"],
      runtime: 55,
      match_score: 92,
      match_score_solo: { [VIEWER_UID]: 94, [PARTNER_UID]: 89 },
      ai_blurb:
        "Slow-burn dystopian office mystery — picks up the Black Mirror + workplace-thriller threads your household keeps returning to.",
      source: "discover",
      scored: true,
      imdb_id: "tt11280740",
      subgenres: ["psychological_thriller"],
      generated_at: ts(daysAgo(1)),
    },
  },
  {
    id: "movie:545611",
    doc: {
      media_type: "movie",
      tmdb_id: 545611,
      title: "Everything Everywhere All at Once",
      year: 2022,
      poster_path: "/w3LxiVYdWWRvEVdn5RBuoQu1IfV.jpg",
      genres: ["Action", "Adventure", "Science Fiction"],
      runtime: 139,
      match_score: 90,
      match_score_solo: { [VIEWER_UID]: 88, [PARTNER_UID]: 92 },
      ai_blurb:
        "Maximalist multiverse comedy with real heart. The pacing matches your Together-mode preference for high-energy without sacrificing emotional payoff.",
      source: "discover",
      scored: true,
      is_oscar_winner: true,
      imdb_id: "tt6710474",
      generated_at: ts(daysAgo(2)),
    },
  },
  {
    id: "tv:136315",
    doc: {
      media_type: "tv",
      tmdb_id: 136315,
      title: "The Bear",
      year: 2022,
      poster_path: "/zPyHvSjxz9KSgFR4FNHl4nLwTRY.jpg",
      genres: ["Drama", "Comedy"],
      runtime: 30,
      match_score: 89,
      match_score_solo: { [VIEWER_UID]: 91, [PARTNER_UID]: 87 },
      ai_blurb:
        "Half-hour kitchen drama with anxiety as a fifth ingredient. Short episodes make it Together-mode friendly on weeknights.",
      source: "discover",
      scored: true,
      imdb_id: "tt14452776",
      generated_at: ts(daysAgo(2)),
    },
  },
  {
    id: "movie:666277",
    doc: {
      media_type: "movie",
      tmdb_id: 666277,
      title: "Past Lives",
      year: 2023,
      poster_path: "/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg",
      genres: ["Romance", "Drama"],
      runtime: 105,
      match_score: 87,
      match_score_solo: { [VIEWER_UID]: 85, [PARTNER_UID]: 89 },
      ai_blurb:
        "Quiet, restrained romance — leans into the unsaid. Jamie's recent A24 streak suggests this would land for Together night.",
      source: "discover",
      scored: true,
      imdb_id: "tt13238346",
      curator: "a24",
      generated_at: ts(daysAgo(3)),
    },
  },
  {
    id: "movie:693134",
    doc: {
      media_type: "movie",
      tmdb_id: 693134,
      title: "Dune: Part Two",
      year: 2024,
      poster_path: "/czembW0Rk1Ke7lCJGahbOhdCuhV.jpg",
      genres: ["Science Fiction", "Adventure"],
      runtime: 167,
      match_score: 86,
      match_score_solo: { [VIEWER_UID]: 90, [PARTNER_UID]: 81 },
      ai_blurb:
        "Big-canvas sci-fi epic — pacing rewards the IMAX framing. Alex's Solo profile leans this way harder than Jamie's does.",
      source: "trending",
      scored: true,
      imdb_id: "tt15239678",
      generated_at: ts(daysAgo(3)),
    },
  },
  {
    id: "movie:915935",
    doc: {
      media_type: "movie",
      tmdb_id: 915935,
      title: "Anatomy of a Fall",
      year: 2023,
      poster_path: "/kQs6keheMwCxJxrzV83VUwFtHkB.jpg",
      genres: ["Thriller", "Drama", "Mystery"],
      runtime: 152,
      match_score: 85,
      match_score_solo: { [VIEWER_UID]: 87, [PARTNER_UID]: 82 },
      ai_blurb:
        "Courtroom procedural meets domestic post-mortem. Long but every minute earns its place.",
      source: "discover",
      scored: true,
      is_oscar_winner: true,
      imdb_id: "tt17009710",
      generated_at: ts(daysAgo(4)),
    },
  },
  {
    id: "tv:60059",
    doc: {
      media_type: "tv",
      tmdb_id: 60059,
      title: "Better Call Saul",
      year: 2015,
      poster_path: "/h3yp2k7Y6SLE8PCbnW8stmgYK6T.jpg",
      genres: ["Crime", "Drama"],
      runtime: 47,
      match_score: 84,
      match_score_solo: { [VIEWER_UID]: 86, [PARTNER_UID]: 82 },
      ai_blurb:
        "Slow-build prequel that outpaces its parent show on character work. 63 episodes — a real commitment, but the payoff curve is steep.",
      source: "discover",
      scored: true,
      imdb_id: "tt3032476",
      generated_at: ts(daysAgo(4)),
    },
  },
  {
    id: "movie:120467",
    doc: {
      media_type: "movie",
      tmdb_id: 120467,
      title: "The Grand Budapest Hotel",
      year: 2014,
      poster_path: "/eWdyYQreja6JGCzqHWXpWHDrrPo.jpg",
      genres: ["Comedy", "Drama"],
      runtime: 100,
      match_score: 82,
      match_score_solo: { [VIEWER_UID]: 80, [PARTNER_UID]: 84 },
      ai_blurb:
        "Anderson at his most ornate. Watch in Together mode — Jamie's taste profile rewards visual whimsy more than Alex's.",
      source: "discover",
      scored: true,
      imdb_id: "tt2278388",
      generated_at: ts(daysAgo(5)),
    },
  },
  {
    id: "movie:546554",
    doc: {
      media_type: "movie",
      tmdb_id: 546554,
      title: "Knives Out",
      year: 2019,
      poster_path: "/pThyQovXQrw2m0s9x82twj48Jq4.jpg",
      genres: ["Comedy", "Crime", "Mystery"],
      runtime: 130,
      match_score: 81,
      match_score_solo: { [VIEWER_UID]: 83, [PARTNER_UID]: 79 },
      ai_blurb:
        "Whodunit with a screwball pulse. Easy Together-mode pick when neither of you wants something heavy.",
      source: "discover",
      scored: true,
      imdb_id: "tt8946378",
      generated_at: ts(daysAgo(5)),
    },
  },
  {
    id: "tv:1535",
    doc: {
      media_type: "tv",
      tmdb_id: 1535,
      title: "Succession",
      year: 2018,
      poster_path: "/7HW47XbkNQ5fiwQFYGWdw9gs144.jpg",
      genres: ["Drama"],
      runtime: 60,
      match_score: 79,
      match_score_solo: { [VIEWER_UID]: 81, [PARTNER_UID]: 77 },
      ai_blurb:
        "Corporate-dynasty drama dressed as black comedy. Four seasons of escalating viciousness, all of it earned.",
      source: "discover",
      scored: true,
      imdb_id: "tt7660850",
      generated_at: ts(daysAgo(6)),
    },
  },
  {
    id: "movie:530385",
    doc: {
      media_type: "movie",
      tmdb_id: 530385,
      title: "Midsommar",
      year: 2019,
      poster_path: "/7LEI8ulZzO5gy9Ww2NVCrKmHeDZ.jpg",
      genres: ["Horror", "Drama"],
      runtime: 148,
      match_score: 77,
      match_score_solo: { [VIEWER_UID]: 79, [PARTNER_UID]: 75 },
      ai_blurb:
        "Folk-horror with daylight as the threat. Slow build, devastating final act. Skip if either of you is in a low-tolerance mood.",
      source: "discover",
      scored: true,
      imdb_id: "tt8772262",
      curator: "a24",
      subgenres: ["cosmic_horror"],
      generated_at: ts(daysAgo(7)),
    },
  },
];

const tonightsPickDoc = {
  tmdb_id: 496243,
  media_type: "movie",
  title: "Parasite",
  poster_path: "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg",
  year: 2019,
  match_score: 94,
  ai_blurb:
    "Tonight's pick — your highest-scored rec you haven't watched yet. Both of you score this 90+ in solo and together.",
  source: "discover",
  updated_at: ts(now),
};

interface WatchEntrySeed {
  id: string;
  doc: Record<string, unknown>;
}

const watchEntries: WatchEntrySeed[] = [
  {
    id: "movie:278",
    doc: {
      media_type: "movie",
      tmdb_id: 278,
      title: "The Shawshank Redemption",
      year: 1994,
      poster_path: "/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg",
      runtime: 142,
      genres: ["Drama", "Crime"],
      overview:
        "Framed in the 1940s for the double murder of his wife and her lover, upstanding banker Andy Dufresne begins a new life at the Shawshank prison...",
      last_watched_at: ts(daysAgo(45)),
      first_watched_at: ts(daysAgo(45)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "trakt",
      added_by: VIEWER_UID,
      added_at: ts(daysAgo(45)),
    },
  },
  {
    id: "tv:1396",
    doc: {
      media_type: "tv",
      tmdb_id: 1396,
      title: "Breaking Bad",
      year: 2008,
      poster_path: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
      runtime: 49,
      genres: ["Drama", "Crime"],
      overview:
        "When Walter White, a New Mexico chemistry teacher, is diagnosed with Stage III cancer and given a prognosis of only two years left to live, he becomes filled with a sense of fearlessness...",
      last_watched_at: ts(daysAgo(7)),
      first_watched_at: ts(daysAgo(90)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "trakt",
      added_by: VIEWER_UID,
      added_at: ts(daysAgo(90)),
      last_season: 5,
      last_episode: 16,
      in_progress_status: "completed",
    },
  },
  {
    id: "movie:155",
    doc: {
      media_type: "movie",
      tmdb_id: 155,
      title: "The Dark Knight",
      year: 2008,
      poster_path: "/qJ2tW6WMUDux911r6m7haRef0WH.jpg",
      runtime: 152,
      genres: ["Action", "Crime", "Drama"],
      last_watched_at: ts(daysAgo(60)),
      first_watched_at: ts(daysAgo(60)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "manual",
      added_at: ts(daysAgo(60)),
    },
  },
  {
    id: "movie:872585",
    doc: {
      media_type: "movie",
      tmdb_id: 872585,
      title: "Oppenheimer",
      year: 2023,
      poster_path: "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg",
      runtime: 181,
      genres: ["Drama", "History"],
      last_watched_at: ts(daysAgo(14)),
      first_watched_at: ts(daysAgo(14)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "trakt",
      added_at: ts(daysAgo(14)),
    },
  },
  {
    id: "tv:1399",
    doc: {
      media_type: "tv",
      tmdb_id: 1399,
      title: "Game of Thrones",
      year: 2011,
      poster_path: "/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg",
      runtime: 60,
      genres: ["Sci-Fi & Fantasy", "Drama", "Action & Adventure"],
      last_watched_at: ts(daysAgo(3)),
      first_watched_at: ts(daysAgo(120)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "trakt",
      added_at: ts(daysAgo(120)),
      last_season: 6,
      last_episode: 4,
      in_progress_status: "watching",
    },
  },
  {
    id: "tv:94997",
    doc: {
      media_type: "tv",
      tmdb_id: 94997,
      title: "House of the Dragon",
      year: 2022,
      poster_path: "/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg",
      runtime: 60,
      genres: ["Sci-Fi & Fantasy", "Drama"],
      last_watched_at: ts(daysAgo(5)),
      first_watched_at: ts(daysAgo(35)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "trakt",
      added_at: ts(daysAgo(35)),
      last_season: 2,
      last_episode: 5,
      in_progress_status: "watching",
    },
  },
  {
    id: "tv:84958",
    doc: {
      media_type: "tv",
      tmdb_id: 84958,
      title: "Loki",
      year: 2021,
      poster_path: "/voHUmluYmKyleFkTu3lOXQG702u.jpg",
      runtime: 50,
      genres: ["Sci-Fi & Fantasy", "Drama"],
      last_watched_at: ts(daysAgo(2)),
      first_watched_at: ts(daysAgo(28)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "trakt",
      added_at: ts(daysAgo(28)),
      last_season: 2,
      last_episode: 3,
      in_progress_status: "watching",
    },
  },
  {
    id: "movie:13",
    doc: {
      media_type: "movie",
      tmdb_id: 13,
      title: "Forrest Gump",
      year: 1994,
      poster_path: "/arw2vcBveWOVZr6pxd9XTd1TdQa.jpg",
      runtime: 142,
      genres: ["Drama", "Comedy", "Romance"],
      last_watched_at: ts(daysAgo(180)),
      first_watched_at: ts(daysAgo(180)),
      watched_by: { [VIEWER_UID]: true, [PARTNER_UID]: true },
      added_source: "manual",
      added_at: ts(daysAgo(180)),
    },
  },
];

interface RatingSeed {
  id: string;
  doc: Record<string, unknown>;
}

function ratingId(uid: string, level: string, targetId: string): string {
  return `${uid}:${level}:${targetId}`;
}
function rating(
  uid: string,
  level: string,
  targetId: string,
  stars: number,
  daysAgoN: number,
  tags: string[] = [],
  pushed = true,
): RatingSeed {
  return {
    id: ratingId(uid, level, targetId),
    doc: {
      uid,
      level,
      target_id: targetId,
      stars,
      tags,
      rated_at: ts(daysAgo(daysAgoN)),
      pushed_to_trakt: pushed,
      context: "together",
    },
  };
}

const ratings: RatingSeed[] = [
  rating(VIEWER_UID, "movie", "movie:278", 5, 45, ["classic", "rewatchable"]),
  rating(PARTNER_UID, "movie", "movie:278", 5, 45, ["classic"]),
  rating(VIEWER_UID, "show", "tv:1396", 5, 7, ["masterpiece"]),
  rating(PARTNER_UID, "show", "tv:1396", 5, 7, ["masterpiece", "tense"]),
  rating(VIEWER_UID, "movie", "movie:155", 5, 60),
  rating(PARTNER_UID, "movie", "movie:155", 4, 60),
  rating(VIEWER_UID, "movie", "movie:872585", 4, 14, ["epic", "overwhelming"]),
  rating(PARTNER_UID, "movie", "movie:872585", 4, 14),
  rating(VIEWER_UID, "movie", "movie:13", 4, 180, [], false),
  rating(PARTNER_UID, "movie", "movie:13", 5, 180, [], false),
];

interface WatchlistSeed {
  id: string;
  doc: Record<string, unknown>;
}

function sharedWatchlistId(mediaType: string, tmdbId: number): string {
  return `shared:shared:${mediaType}:${tmdbId}`;
}

const watchlist: WatchlistSeed[] = [
  {
    id: sharedWatchlistId("movie", 496243),
    doc: {
      media_type: "movie",
      tmdb_id: 496243,
      title: "Parasite",
      year: 2019,
      poster_path: "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg",
      genres: ["Thriller", "Comedy", "Drama"],
      runtime: 132,
      added_by: VIEWER_UID,
      added_at: ts(daysAgo(2)),
      added_source: "recommendation",
      scope: "shared",
    },
  },
  {
    id: sharedWatchlistId("tv", 95396),
    doc: {
      media_type: "tv",
      tmdb_id: 95396,
      title: "Severance",
      year: 2022,
      poster_path: "/lFf6LLrQjYldcZItzOkGmMMigP7.jpg",
      genres: ["Sci-Fi & Fantasy", "Mystery", "Drama"],
      runtime: 55,
      added_by: PARTNER_UID,
      added_at: ts(daysAgo(4)),
      added_source: "recommendation",
      scope: "shared",
    },
  },
  {
    id: sharedWatchlistId("movie", 545611),
    doc: {
      media_type: "movie",
      tmdb_id: 545611,
      title: "Everything Everywhere All at Once",
      year: 2022,
      poster_path: "/w3LxiVYdWWRvEVdn5RBuoQu1IfV.jpg",
      genres: ["Action", "Adventure", "Science Fiction"],
      runtime: 139,
      added_by: VIEWER_UID,
      added_at: ts(daysAgo(8)),
      added_source: "concierge",
      scope: "shared",
    },
  },
  {
    id: sharedWatchlistId("movie", 666277),
    doc: {
      media_type: "movie",
      tmdb_id: 666277,
      title: "Past Lives",
      year: 2023,
      poster_path: "/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg",
      genres: ["Romance", "Drama"],
      runtime: 105,
      added_by: PARTNER_UID,
      added_at: ts(daysAgo(11)),
      added_source: "manual",
      scope: "shared",
    },
  },
  {
    id: sharedWatchlistId("movie", 693134),
    doc: {
      media_type: "movie",
      tmdb_id: 693134,
      title: "Dune: Part Two",
      year: 2024,
      poster_path: "/czembW0Rk1Ke7lCJGahbOhdCuhV.jpg",
      genres: ["Science Fiction", "Adventure"],
      runtime: 167,
      added_by: VIEWER_UID,
      added_at: ts(daysAgo(15)),
      added_source: "share",
      scope: "shared",
    },
  },
  {
    id: sharedWatchlistId("tv", 136315),
    doc: {
      media_type: "tv",
      tmdb_id: 136315,
      title: "The Bear",
      year: 2022,
      poster_path: "/zPyHvSjxz9KSgFR4FNHl4nLwTRY.jpg",
      genres: ["Drama", "Comedy"],
      runtime: 30,
      added_by: PARTNER_UID,
      added_at: ts(daysAgo(20)),
      added_source: "recommendation",
      scope: "shared",
    },
  },
];

interface NotInterestedSeed {
  id: string;
  doc: Record<string, unknown>;
}

function sharedNotInterestedId(mediaType: string, tmdbId: number): string {
  return `shared:shared:${mediaType}:${tmdbId}`;
}

const notInterested: NotInterestedSeed[] = [
  {
    id: sharedNotInterestedId("movie", 680),
    doc: {
      media_type: "movie",
      tmdb_id: 680,
      title: "Pulp Fiction",
      poster_path: "/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg",
      scope: "shared",
      marked_by_uid: VIEWER_UID,
      marked_at: ts(daysAgo(12)),
    },
  },
  {
    id: sharedNotInterestedId("tv", 4607),
    doc: {
      media_type: "tv",
      tmdb_id: 4607,
      title: "Lost",
      poster_path: "/og6S0aTZU6YUJAbqxeKjCa3kY1E.jpg",
      scope: "shared",
      marked_by_uid: PARTNER_UID,
      marked_at: ts(daysAgo(25)),
    },
  },
];

// Taste profile — single doc at /households/{hh}/tasteProfile/current.
// (The Flutter app reads /tasteProfile/{id}; conventional id is 'current'
// for the singleton case. demo_overrides.dart streams the map directly,
// bypassing doc lookup — so the on-disk doc id only matters if the real
// tasteProfileProvider is used, which it will be here in the real-Firebase
// screenshots run.)
const tasteProfile = {
  combined: {
    top_genres: [
      { genre: "Drama", weight: 0.28 },
      { genre: "Thriller", weight: 0.22 },
      { genre: "Crime", weight: 0.16 },
      { genre: "Sci-Fi & Fantasy", weight: 0.14 },
      { genre: "Comedy", weight: 0.12 },
    ],
    compatibility: { within_1_star_pct: 0.78 },
  },
  per_user_solo: {
    [VIEWER_UID]: {
      top_genres: [
        { genre: "Thriller", weight: 0.32 },
        { genre: "Science Fiction", weight: 0.24 },
        { genre: "Crime", weight: 0.18 },
      ],
    },
    [PARTNER_UID]: {
      top_genres: [
        { genre: "Drama", weight: 0.34 },
        { genre: "Romance", weight: 0.21 },
        { genre: "Comedy", weight: 0.17 },
      ],
    },
  },
  per_user_together: {
    [VIEWER_UID]: {
      top_genres: [
        { genre: "Drama", weight: 0.30 },
        { genre: "Thriller", weight: 0.24 },
      ],
    },
    [PARTNER_UID]: {
      top_genres: [
        { genre: "Drama", weight: 0.32 },
        { genre: "Thriller", weight: 0.20 },
      ],
    },
  },
  member_uids: [VIEWER_UID, PARTNER_UID],
  updated_at: ts(now),
};

// ─────────────────────────────────────────────────────────────────────
// firebase-admin init + batch-write helpers
// ─────────────────────────────────────────────────────────────────────

function initAdmin(): void {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inline) {
    const parsed = JSON.parse(inline);
    initializeApp({ credential: cert(parsed), projectId: parsed.project_id });
    return;
  }
  // applicationDefault() honours GOOGLE_APPLICATION_CREDENTIALS or gcloud
  // user creds — both work for local runs.
  initializeApp({ credential: applicationDefault() });
}

/**
 * Firestore caps batches at 500 ops. Wraps a list of (path, doc) pairs in
 * chunked WriteBatches and commits them serially.
 */
async function commitInChunks(
  ops: Array<{ path: string; doc: Record<string, unknown> }>,
): Promise<void> {
  const db = getFirestore();
  const CHUNK = 450;
  let batch: WriteBatch = db.batch();
  let pending = 0;
  for (const op of ops) {
    batch.set(db.doc(op.path), op.doc);
    pending++;
    if (pending >= CHUNK) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) {
    await batch.commit();
  }
}

async function seed(): Promise<void> {
  const ops: Array<{ path: string; doc: Record<string, unknown> }> = [];

  // Household root doc — minimal, mirrors what createHousehold() writes.
  ops.push({
    path: `households/${HOUSEHOLD_ID}`,
    doc: {
      createdBy: VIEWER_UID,
      created_at: ts(daysAgo(120)),
      invite_code: "screenshot-test-household",
    },
  });

  // Members — both viewer and partner. display_name shows up in the AppBar
  // and Profile sheet so the screenshots look like a named household
  // rather than "Member" / "Member".
  ops.push({
    path: `households/${HOUSEHOLD_ID}/members/${VIEWER_UID}`,
    doc: {
      display_name: "Alex",
      email: "alex@example.com",
      avatar_url: null,
      joined_at: ts(daysAgo(120)),
      trakt_access_token: null,
      trakt_refresh_token: null,
      trakt_user_id: null,
      last_trakt_sync: null,
      default_mode: "together",
    },
  });
  ops.push({
    path: `households/${HOUSEHOLD_ID}/members/${PARTNER_UID}`,
    doc: {
      display_name: "Jamie",
      email: "jamie@example.com",
      avatar_url: null,
      joined_at: ts(daysAgo(115)),
      trakt_access_token: null,
      trakt_refresh_token: null,
      trakt_user_id: null,
      last_trakt_sync: null,
      default_mode: "together",
    },
  });

  // /users/{uid} → household pointer. The viewer is the one we sign in as,
  // so this is the load-bearing pointer; the partner's pointer is mirrored
  // for symmetry but not strictly required by any read path the screenshot
  // run exercises.
  ops.push({
    path: `users/${VIEWER_UID}`,
    doc: { householdId: HOUSEHOLD_ID },
  });
  ops.push({
    path: `users/${PARTNER_UID}`,
    doc: { householdId: HOUSEHOLD_ID },
  });

  // Recommendations.
  for (const rec of recommendations) {
    ops.push({
      path: `households/${HOUSEHOLD_ID}/recommendations/${rec.id}`,
      doc: rec.doc,
    });
  }

  // Tonight's pick — singleton doc, conventional id 'current'.
  ops.push({
    path: `households/${HOUSEHOLD_ID}/tonightsPick/current`,
    doc: tonightsPickDoc,
  });

  // Watch entries.
  for (const we of watchEntries) {
    ops.push({
      path: `households/${HOUSEHOLD_ID}/watchEntries/${we.id}`,
      doc: we.doc,
    });
  }

  // Ratings.
  for (const r of ratings) {
    ops.push({
      path: `households/${HOUSEHOLD_ID}/ratings/${r.id}`,
      doc: r.doc,
    });
  }

  // Watchlist.
  for (const w of watchlist) {
    ops.push({
      path: `households/${HOUSEHOLD_ID}/watchlist/${w.id}`,
      doc: w.doc,
    });
  }

  // Not-interested.
  for (const ni of notInterested) {
    ops.push({
      path: `households/${HOUSEHOLD_ID}/notInterested/${ni.id}`,
      doc: ni.doc,
    });
  }

  // Taste profile (singleton).
  ops.push({
    path: `households/${HOUSEHOLD_ID}/tasteProfile/current`,
    doc: tasteProfile,
  });

  console.log(`Seeding ${ops.length} docs into household ${HOUSEHOLD_ID}…`);
  await commitInChunks(ops);
  console.log(`OK — ${ops.length} docs written.`);
}

async function mintToken(): Promise<void> {
  // Custom-token expiry is fixed by Firebase Auth at 1 hour; the resulting
  // session lasts much longer. Plenty for a screenshot run (~3-5 min).
  const token = await getAuth().createCustomToken(VIEWER_UID);
  // Print ONLY the token to stdout so the GHA workflow can capture it
  // cleanly via `$(node …)` or step output.
  process.stdout.write(token);
}

(async () => {
  const cmd = process.argv[2];
  if (cmd !== "seed" && cmd !== "mint-token") {
    console.error("Usage: ts-node screenshots_setup.ts <seed|mint-token>");
    process.exit(1);
  }
  initAdmin();
  try {
    if (cmd === "seed") await seed();
    else await mintToken();
  } catch (err) {
    console.error("FAIL", err);
    process.exit(1);
  }
})();
