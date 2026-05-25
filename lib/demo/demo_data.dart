/// Curated mock data for demo mode (DEMO_MODE=true builds).
///
/// All values are realistic enough that Play Store reviewers + prospective
/// users see a plausible, well-populated household across every screen
/// the screenshot suite visits. Poster paths are REAL TMDB paths against
/// real titles — TMDB's image CDN is public and unauthenticated, so the
/// emulator can fetch posters during a screenshot run without any API
/// key. Titles span genres (drama, thriller, comedy, sci-fi, action) and
/// eras (1994–2024) so the recommendations list reads as variety, not
/// algorithmic monoculture.
///
/// Keep this file the SINGLE source of truth for demo content. Provider
/// overrides in `demo_overrides.dart` build their streams from these
/// constants — adding a new title here flows through to every screen
/// that consumes it.
library;

import '../models/not_interested_item.dart';
import '../models/rating.dart';
import '../models/recommendation.dart';
import '../models/watch_entry.dart';
import '../models/watchlist_item.dart';
import '../providers/rewatch_provider.dart' show RewatchTitle;
import '../providers/tonights_pick_provider.dart';
import '../providers/upcoming_provider.dart' show UpcomingTitle;
import '../providers/upnext_provider.dart' show UpNextEpisode;
import 'demo_mode.dart';

// ─────────────────────────────────────────────────────────────────────
// Time anchors — relative to "now" so the screenshots always feel fresh
// regardless of when the build runs.
// ─────────────────────────────────────────────────────────────────────

final DateTime _now = DateTime.now();
DateTime _daysAgo(int n) => _now.subtract(Duration(days: n));
DateTime _daysFromNow(int n) => _now.add(Duration(days: n));

// ─────────────────────────────────────────────────────────────────────
// Recommendations (Home screen rec list)
//
// 12 titles, all with realistic match scores (75–94), real TMDB IDs +
// poster paths, varied genres + eras. AI blurbs are short, opinionated,
// not generic — exactly the voice the real Gemini scorer produces.
// ─────────────────────────────────────────────────────────────────────

final List<Recommendation> demoRecommendations = [
  Recommendation(
    id: 'movie:496243',
    mediaType: 'movie',
    tmdbId: 496243,
    title: 'Parasite',
    year: 2019,
    posterPath: '/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg',
    genres: const ['Thriller', 'Comedy', 'Drama'],
    runtime: 132,
    matchScore: 94,
    matchScoreSolo: const {kDemoUid: 96, kDemoPartnerUid: 92},
    aiBlurb:
        'A genre-bending thriller you both rated highly recent overlaps with — '
        'Bong\'s class-warfare suspense lands every beat.',
    aiBlurbSolo: const {
      kDemoUid:
          'Your top-rated thriller of the last year was Anatomy of a Fall. '
              'Parasite\'s pivot-on-a-dime tonal shifts are in the same lane.',
    },
    source: 'discover',
    scored: true,
    isOscarWinner: true,
    imdbId: 'tt6751668',
    generatedAt: _daysAgo(1),
  ),
  Recommendation(
    id: 'tv:95396',
    mediaType: 'tv',
    tmdbId: 95396,
    title: 'Severance',
    year: 2022,
    posterPath: '/lFf6LLrQjYldcZItzOkGmMMigP7.jpg',
    genres: const ['Sci-Fi & Fantasy', 'Mystery', 'Drama'],
    runtime: 55,
    matchScore: 92,
    matchScoreSolo: const {kDemoUid: 94, kDemoPartnerUid: 89},
    aiBlurb:
        'Slow-burn dystopian office mystery — picks up the Black Mirror + '
        'workplace-thriller threads your household keeps returning to.',
    source: 'discover',
    scored: true,
    imdbId: 'tt11280740',
    subgenres: const {'psychological_thriller'},
    generatedAt: _daysAgo(1),
  ),
  Recommendation(
    id: 'movie:545611',
    mediaType: 'movie',
    tmdbId: 545611,
    title: 'Everything Everywhere All at Once',
    year: 2022,
    posterPath: '/w3LxiVYdWWRvEVdn5RBuoQu1IfV.jpg',
    genres: const ['Action', 'Adventure', 'Science Fiction'],
    runtime: 139,
    matchScore: 90,
    matchScoreSolo: const {kDemoUid: 88, kDemoPartnerUid: 92},
    aiBlurb:
        'Maximalist multiverse comedy with real heart. The pacing matches '
        'your Together-mode preference for high-energy without sacrificing '
        'emotional payoff.',
    source: 'discover',
    scored: true,
    isOscarWinner: true,
    imdbId: 'tt6710474',
    generatedAt: _daysAgo(2),
  ),
  Recommendation(
    id: 'tv:136315',
    mediaType: 'tv',
    tmdbId: 136315,
    title: 'The Bear',
    year: 2022,
    posterPath: '/zPyHvSjxz9KSgFR4FNHl4nLwTRY.jpg',
    genres: const ['Drama', 'Comedy'],
    runtime: 30,
    matchScore: 89,
    matchScoreSolo: const {kDemoUid: 91, kDemoPartnerUid: 87},
    aiBlurb:
        'Half-hour kitchen drama with anxiety as a fifth ingredient. '
        'Short episodes make it Together-mode friendly on weeknights.',
    source: 'discover',
    scored: true,
    imdbId: 'tt14452776',
    generatedAt: _daysAgo(2),
  ),
  Recommendation(
    id: 'movie:666277',
    mediaType: 'movie',
    tmdbId: 666277,
    title: 'Past Lives',
    year: 2023,
    posterPath: '/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg',
    genres: const ['Romance', 'Drama'],
    runtime: 105,
    matchScore: 87,
    matchScoreSolo: const {kDemoUid: 85, kDemoPartnerUid: 89},
    aiBlurb:
        'Quiet, restrained romance — leans into the unsaid. Jamie\'s '
        'recent A24 streak suggests this would land for Together night.',
    source: 'discover',
    scored: true,
    imdbId: 'tt13238346',
    curator: 'a24',
    generatedAt: _daysAgo(3),
  ),
  Recommendation(
    id: 'movie:693134',
    mediaType: 'movie',
    tmdbId: 693134,
    title: 'Dune: Part Two',
    year: 2024,
    posterPath: '/czembW0Rk1Ke7lCJGahbOhdCuhV.jpg',
    genres: const ['Science Fiction', 'Adventure'],
    runtime: 167,
    matchScore: 86,
    matchScoreSolo: const {kDemoUid: 90, kDemoPartnerUid: 81},
    aiBlurb:
        'Big-canvas sci-fi epic — pacing rewards the IMAX framing. Alex\'s '
        'Solo profile leans this way harder than Jamie\'s does.',
    source: 'trending',
    scored: true,
    imdbId: 'tt15239678',
    generatedAt: _daysAgo(3),
  ),
  Recommendation(
    id: 'movie:915935',
    mediaType: 'movie',
    tmdbId: 915935,
    title: 'Anatomy of a Fall',
    year: 2023,
    posterPath: '/kQs6keheMwCxJxrzV83VUwFtHkB.jpg',
    genres: const ['Thriller', 'Drama', 'Mystery'],
    runtime: 152,
    matchScore: 85,
    matchScoreSolo: const {kDemoUid: 87, kDemoPartnerUid: 82},
    aiBlurb:
        'Courtroom procedural meets domestic post-mortem. Long but '
        'every minute earns its place.',
    source: 'discover',
    scored: true,
    isOscarWinner: true,
    imdbId: 'tt17009710',
    generatedAt: _daysAgo(4),
  ),
  Recommendation(
    id: 'tv:60059',
    mediaType: 'tv',
    tmdbId: 60059,
    title: 'Better Call Saul',
    year: 2015,
    posterPath: '/h3yp2k7Y6SLE8PCbnW8stmgYK6T.jpg',
    genres: const ['Crime', 'Drama'],
    runtime: 47,
    matchScore: 84,
    matchScoreSolo: const {kDemoUid: 86, kDemoPartnerUid: 82},
    aiBlurb:
        'Slow-build prequel that outpaces its parent show on character '
        'work. 63 episodes — a real commitment, but the payoff curve is steep.',
    source: 'discover',
    scored: true,
    imdbId: 'tt3032476',
    generatedAt: _daysAgo(4),
  ),
  Recommendation(
    id: 'movie:120467',
    mediaType: 'movie',
    tmdbId: 120467,
    title: 'The Grand Budapest Hotel',
    year: 2014,
    posterPath: '/eWdyYQreja6JGCzqHWXpWHDrrPo.jpg',
    genres: const ['Comedy', 'Drama'],
    runtime: 100,
    matchScore: 82,
    matchScoreSolo: const {kDemoUid: 80, kDemoPartnerUid: 84},
    aiBlurb:
        'Anderson at his most ornate. Watch in Together mode — Jamie\'s '
        'taste profile rewards visual whimsy more than Alex\'s.',
    source: 'discover',
    scored: true,
    imdbId: 'tt2278388',
    generatedAt: _daysAgo(5),
  ),
  Recommendation(
    id: 'movie:546554',
    mediaType: 'movie',
    tmdbId: 546554,
    title: 'Knives Out',
    year: 2019,
    posterPath: '/pThyQovXQrw2m0s9x82twj48Jq4.jpg',
    genres: const ['Comedy', 'Crime', 'Mystery'],
    runtime: 130,
    matchScore: 81,
    matchScoreSolo: const {kDemoUid: 83, kDemoPartnerUid: 79},
    aiBlurb:
        'Whodunit with a screwball pulse. Easy Together-mode pick when '
        'neither of you wants something heavy.',
    source: 'discover',
    scored: true,
    imdbId: 'tt8946378',
    generatedAt: _daysAgo(5),
  ),
  Recommendation(
    id: 'tv:1535',
    mediaType: 'tv',
    tmdbId: 1535,
    title: 'Succession',
    year: 2018,
    posterPath: '/7HW47XbkNQ5fiwQFYGWdw9gs144.jpg',
    genres: const ['Drama'],
    runtime: 60,
    matchScore: 79,
    matchScoreSolo: const {kDemoUid: 81, kDemoPartnerUid: 77},
    aiBlurb:
        'Corporate-dynasty drama dressed as black comedy. Four seasons '
        'of escalating viciousness, all of it earned.',
    source: 'discover',
    scored: true,
    imdbId: 'tt7660850',
    generatedAt: _daysAgo(6),
  ),
  Recommendation(
    id: 'movie:530385',
    mediaType: 'movie',
    tmdbId: 530385,
    title: 'Midsommar',
    year: 2019,
    posterPath: '/7LEI8ulZzO5gy9Ww2NVCrKmHeDZ.jpg',
    genres: const ['Horror', 'Drama'],
    runtime: 148,
    matchScore: 77,
    matchScoreSolo: const {kDemoUid: 79, kDemoPartnerUid: 75},
    aiBlurb:
        'Folk-horror with daylight as the threat. Slow build, devastating '
        'final act. Skip if either of you is in a low-tolerance mood.',
    source: 'discover',
    scored: true,
    imdbId: 'tt8772262',
    curator: 'a24',
    subgenres: const {'cosmic_horror'},
    generatedAt: _daysAgo(7),
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Tonight's Pick
// ─────────────────────────────────────────────────────────────────────

final TonightsPick demoTonightsPick = TonightsPick(
  tmdbId: 496243,
  mediaType: 'movie',
  title: 'Parasite',
  posterPath: '/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg',
  year: 2019,
  matchScore: 94,
  aiBlurb:
      'Tonight\'s pick — your highest-scored rec you haven\'t watched yet. '
      'Both of you score this 90+ in solo and together.',
  source: 'discover',
  updatedAt: _now,
);

// ─────────────────────────────────────────────────────────────────────
// Watch entries — what the household has already watched
//
// Mix of:
//   - finished movies + finished shows (Watched tab)
//   - in-progress TV (Watching tab + Up Next carousel)
// Enough volume to make Stats look populated.
// ─────────────────────────────────────────────────────────────────────

final List<WatchEntry> demoWatchEntries = [
  WatchEntry(
    id: 'movie:278',
    mediaType: 'movie',
    tmdbId: 278,
    title: 'The Shawshank Redemption',
    year: 1994,
    posterPath: '/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg',
    runtime: 142,
    genres: const ['Drama', 'Crime'],
    overview:
        'Framed in the 1940s for the double murder of his wife and her lover, '
        'upstanding banker Andy Dufresne begins a new life at the Shawshank '
        'prison...',
    lastWatchedAt: _daysAgo(45),
    firstWatchedAt: _daysAgo(45),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'trakt',
    addedBy: kDemoUid,
    addedAt: _daysAgo(45),
  ),
  WatchEntry(
    id: 'tv:1396',
    mediaType: 'tv',
    tmdbId: 1396,
    title: 'Breaking Bad',
    year: 2008,
    posterPath: '/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
    runtime: 49,
    genres: const ['Drama', 'Crime'],
    overview:
        'When Walter White, a New Mexico chemistry teacher, is diagnosed with '
        'Stage III cancer and given a prognosis of only two years left to live, '
        'he becomes filled with a sense of fearlessness...',
    lastWatchedAt: _daysAgo(7),
    firstWatchedAt: _daysAgo(90),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'trakt',
    addedBy: kDemoUid,
    addedAt: _daysAgo(90),
    lastSeason: 5,
    lastEpisode: 16,
    inProgressStatus: 'completed',
  ),
  WatchEntry(
    id: 'movie:155',
    mediaType: 'movie',
    tmdbId: 155,
    title: 'The Dark Knight',
    year: 2008,
    posterPath: '/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
    runtime: 152,
    genres: const ['Action', 'Crime', 'Drama'],
    lastWatchedAt: _daysAgo(60),
    firstWatchedAt: _daysAgo(60),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'manual',
    addedAt: _daysAgo(60),
  ),
  WatchEntry(
    id: 'movie:872585',
    mediaType: 'movie',
    tmdbId: 872585,
    title: 'Oppenheimer',
    year: 2023,
    posterPath: '/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
    runtime: 181,
    genres: const ['Drama', 'History'],
    lastWatchedAt: _daysAgo(14),
    firstWatchedAt: _daysAgo(14),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'trakt',
    addedAt: _daysAgo(14),
  ),
  WatchEntry(
    id: 'tv:1399',
    mediaType: 'tv',
    tmdbId: 1399,
    title: 'Game of Thrones',
    year: 2011,
    posterPath: '/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg',
    runtime: 60,
    genres: const ['Sci-Fi & Fantasy', 'Drama', 'Action & Adventure'],
    lastWatchedAt: _daysAgo(3),
    firstWatchedAt: _daysAgo(120),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'trakt',
    addedAt: _daysAgo(120),
    lastSeason: 6,
    lastEpisode: 4,
    inProgressStatus: 'watching',
  ),
  WatchEntry(
    id: 'tv:94997',
    mediaType: 'tv',
    tmdbId: 94997,
    title: 'House of the Dragon',
    year: 2022,
    posterPath: '/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg',
    runtime: 60,
    genres: const ['Sci-Fi & Fantasy', 'Drama'],
    lastWatchedAt: _daysAgo(5),
    firstWatchedAt: _daysAgo(35),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'trakt',
    addedAt: _daysAgo(35),
    lastSeason: 2,
    lastEpisode: 5,
    inProgressStatus: 'watching',
  ),
  WatchEntry(
    id: 'tv:84958',
    mediaType: 'tv',
    tmdbId: 84958,
    title: 'Loki',
    year: 2021,
    posterPath: '/voHUmluYmKyleFkTu3lOXQG702u.jpg',
    runtime: 50,
    genres: const ['Sci-Fi & Fantasy', 'Drama'],
    lastWatchedAt: _daysAgo(2),
    firstWatchedAt: _daysAgo(28),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'trakt',
    addedAt: _daysAgo(28),
    lastSeason: 2,
    lastEpisode: 3,
    inProgressStatus: 'watching',
  ),
  WatchEntry(
    id: 'movie:13',
    mediaType: 'movie',
    tmdbId: 13,
    title: 'Forrest Gump',
    year: 1994,
    posterPath: '/arw2vcBveWOVZr6pxd9XTd1TdQa.jpg',
    runtime: 142,
    genres: const ['Drama', 'Comedy', 'Romance'],
    lastWatchedAt: _daysAgo(180),
    firstWatchedAt: _daysAgo(180),
    watchedBy: const {kDemoUid: true, kDemoPartnerUid: true},
    addedSource: 'manual',
    addedAt: _daysAgo(180),
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Ratings — 1 per finished movie/show entry, attributed to both users
//
// Stars chosen so the household stats screen reads as a happy
// well-calibrated household (mostly 4s and 5s).
// ─────────────────────────────────────────────────────────────────────

final List<Rating> demoRatings = [
  // The Shawshank Redemption — both 5
  Rating(
    id: Rating.buildId(kDemoUid, 'movie', 'movie:278'),
    uid: kDemoUid,
    level: 'movie',
    targetId: 'movie:278',
    stars: 5,
    tags: const ['classic', 'rewatchable'],
    ratedAt: _daysAgo(45),
    pushedToTrakt: true,
    context: 'together',
  ),
  Rating(
    id: Rating.buildId(kDemoPartnerUid, 'movie', 'movie:278'),
    uid: kDemoPartnerUid,
    level: 'movie',
    targetId: 'movie:278',
    stars: 5,
    tags: const ['classic'],
    ratedAt: _daysAgo(45),
    pushedToTrakt: true,
    context: 'together',
  ),
  // Breaking Bad — 5 and 5
  Rating(
    id: Rating.buildId(kDemoUid, 'show', 'tv:1396'),
    uid: kDemoUid,
    level: 'show',
    targetId: 'tv:1396',
    stars: 5,
    tags: const ['masterpiece'],
    ratedAt: _daysAgo(7),
    pushedToTrakt: true,
    context: 'together',
  ),
  Rating(
    id: Rating.buildId(kDemoPartnerUid, 'show', 'tv:1396'),
    uid: kDemoPartnerUid,
    level: 'show',
    targetId: 'tv:1396',
    stars: 5,
    tags: const ['masterpiece', 'tense'],
    ratedAt: _daysAgo(7),
    pushedToTrakt: true,
    context: 'together',
  ),
  // The Dark Knight — 5 and 4
  Rating(
    id: Rating.buildId(kDemoUid, 'movie', 'movie:155'),
    uid: kDemoUid,
    level: 'movie',
    targetId: 'movie:155',
    stars: 5,
    ratedAt: _daysAgo(60),
    pushedToTrakt: true,
    context: 'together',
  ),
  Rating(
    id: Rating.buildId(kDemoPartnerUid, 'movie', 'movie:155'),
    uid: kDemoPartnerUid,
    level: 'movie',
    targetId: 'movie:155',
    stars: 4,
    ratedAt: _daysAgo(60),
    pushedToTrakt: true,
    context: 'together',
  ),
  // Oppenheimer — 4 and 4
  Rating(
    id: Rating.buildId(kDemoUid, 'movie', 'movie:872585'),
    uid: kDemoUid,
    level: 'movie',
    targetId: 'movie:872585',
    stars: 4,
    tags: const ['epic', 'overwhelming'],
    ratedAt: _daysAgo(14),
    pushedToTrakt: true,
    context: 'together',
  ),
  Rating(
    id: Rating.buildId(kDemoPartnerUid, 'movie', 'movie:872585'),
    uid: kDemoPartnerUid,
    level: 'movie',
    targetId: 'movie:872585',
    stars: 4,
    ratedAt: _daysAgo(14),
    pushedToTrakt: true,
    context: 'together',
  ),
  // Forrest Gump — 4 and 5
  Rating(
    id: Rating.buildId(kDemoUid, 'movie', 'movie:13'),
    uid: kDemoUid,
    level: 'movie',
    targetId: 'movie:13',
    stars: 4,
    ratedAt: _daysAgo(180),
    pushedToTrakt: false,
    context: 'together',
  ),
  Rating(
    id: Rating.buildId(kDemoPartnerUid, 'movie', 'movie:13'),
    uid: kDemoPartnerUid,
    level: 'movie',
    targetId: 'movie:13',
    stars: 5,
    ratedAt: _daysAgo(180),
    pushedToTrakt: false,
    context: 'together',
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Watchlist (Library Saved tab) — 6 shared, mostly recent additions
// ─────────────────────────────────────────────────────────────────────

final List<WatchlistItem> demoWatchlist = [
  WatchlistItem(
    id: WatchlistItem.buildId('movie', 496243),
    mediaType: 'movie',
    tmdbId: 496243,
    title: 'Parasite',
    year: 2019,
    posterPath: '/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg',
    genres: const ['Thriller', 'Comedy', 'Drama'],
    runtime: 132,
    addedBy: kDemoUid,
    addedAt: _daysAgo(2),
    addedSource: 'recommendation',
  ),
  WatchlistItem(
    id: WatchlistItem.buildId('tv', 95396),
    mediaType: 'tv',
    tmdbId: 95396,
    title: 'Severance',
    year: 2022,
    posterPath: '/lFf6LLrQjYldcZItzOkGmMMigP7.jpg',
    genres: const ['Sci-Fi & Fantasy', 'Mystery', 'Drama'],
    runtime: 55,
    addedBy: kDemoPartnerUid,
    addedAt: _daysAgo(4),
    addedSource: 'recommendation',
  ),
  WatchlistItem(
    id: WatchlistItem.buildId('movie', 545611),
    mediaType: 'movie',
    tmdbId: 545611,
    title: 'Everything Everywhere All at Once',
    year: 2022,
    posterPath: '/w3LxiVYdWWRvEVdn5RBuoQu1IfV.jpg',
    genres: const ['Action', 'Adventure', 'Science Fiction'],
    runtime: 139,
    addedBy: kDemoUid,
    addedAt: _daysAgo(8),
    addedSource: 'concierge',
  ),
  WatchlistItem(
    id: WatchlistItem.buildId('movie', 666277),
    mediaType: 'movie',
    tmdbId: 666277,
    title: 'Past Lives',
    year: 2023,
    posterPath: '/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg',
    genres: const ['Romance', 'Drama'],
    runtime: 105,
    addedBy: kDemoPartnerUid,
    addedAt: _daysAgo(11),
    addedSource: 'manual',
  ),
  WatchlistItem(
    id: WatchlistItem.buildId('movie', 693134),
    mediaType: 'movie',
    tmdbId: 693134,
    title: 'Dune: Part Two',
    year: 2024,
    posterPath: '/czembW0Rk1Ke7lCJGahbOhdCuhV.jpg',
    genres: const ['Science Fiction', 'Adventure'],
    runtime: 167,
    addedBy: kDemoUid,
    addedAt: _daysAgo(15),
    addedSource: 'share',
  ),
  WatchlistItem(
    id: WatchlistItem.buildId('tv', 136315),
    mediaType: 'tv',
    tmdbId: 136315,
    title: 'The Bear',
    year: 2022,
    posterPath: '/zPyHvSjxz9KSgFR4FNHl4nLwTRY.jpg',
    genres: const ['Drama', 'Comedy'],
    runtime: 30,
    addedBy: kDemoPartnerUid,
    addedAt: _daysAgo(20),
    addedSource: 'recommendation',
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Not-interested items — 2 titles the household hid from recs
// (small so the Library Hidden tab has content without dominating)
// ─────────────────────────────────────────────────────────────────────

final List<NotInterestedItem> demoNotInterested = [
  NotInterestedItem(
    id: NotInterestedItem.buildId('movie', 680),
    mediaType: 'movie',
    tmdbId: 680,
    title: 'Pulp Fiction',
    posterPath: '/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg',
    scope: 'shared',
    markedByUid: kDemoUid,
    markedAt: _daysAgo(12),
  ),
  NotInterestedItem(
    id: NotInterestedItem.buildId('tv', 4607),
    mediaType: 'tv',
    tmdbId: 4607,
    title: 'Lost',
    posterPath: '/og6S0aTZU6YUJAbqxeKjCa3kY1E.jpg',
    scope: 'shared',
    markedByUid: kDemoPartnerUid,
    markedAt: _daysAgo(25),
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Up Next — episodes airing soon for in-progress shows
// ─────────────────────────────────────────────────────────────────────

final List<UpNextEpisode> demoUpNext = [
  UpNextEpisode(
    tmdbId: 1399,
    showTitle: 'Game of Thrones',
    showPosterPath: '/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg',
    season: 6,
    number: 5,
    episodeName: 'The Door',
    airDate: _daysFromNow(2),
    daysUntilAir: 2,
  ),
  UpNextEpisode(
    tmdbId: 94997,
    showTitle: 'House of the Dragon',
    showPosterPath: '/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg',
    season: 2,
    number: 6,
    episodeName: 'Smallfolk',
    airDate: _daysFromNow(4),
    daysUntilAir: 4,
  ),
  UpNextEpisode(
    tmdbId: 84958,
    showTitle: 'Loki',
    showPosterPath: '/voHUmluYmKyleFkTu3lOXQG702u.jpg',
    season: 2,
    number: 4,
    episodeName: 'Heart of the TVA',
    airDate: _daysFromNow(6),
    daysUntilAir: 6,
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Upcoming for you (TMDB-sourced, taste-ranked, near-future releases)
// ─────────────────────────────────────────────────────────────────────

final List<UpcomingTitle> demoUpcoming = [
  UpcomingTitle(
    mediaType: 'movie',
    tmdbId: 1241982,
    title: 'Moana 2',
    posterPath: '/wjGABNXEFqdRfJ2cE7Z9Yt4uxBN.jpg',
    releaseDate: _daysFromNow(7),
    genres: const ['Animation', 'Adventure', 'Family'],
    matchScore: 68,
  ),
  UpcomingTitle(
    mediaType: 'movie',
    tmdbId: 762509,
    title: 'Mufasa: The Lion King',
    posterPath: '/9bXHaLlsFYpJUutg4E6WXAjaxDi.jpg',
    releaseDate: _daysFromNow(14),
    genres: const ['Adventure', 'Family', 'Animation'],
    matchScore: 65,
  ),
  UpcomingTitle(
    mediaType: 'tv',
    tmdbId: 1399,
    title: 'Game of Thrones',
    posterPath: '/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg',
    releaseDate: _daysFromNow(2),
    genres: const ['Sci-Fi & Fantasy', 'Drama'],
    matchScore: 91,
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Rewatch for you (past favorites the household hasn't watched in months)
// ─────────────────────────────────────────────────────────────────────

final List<RewatchTitle> demoRewatch = [
  RewatchTitle(
    mediaType: 'movie',
    tmdbId: 278,
    title: 'The Shawshank Redemption',
    posterPath: '/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg',
    stars: 5,
    lastWatchedAt: _daysAgo(45),
  ),
  RewatchTitle(
    mediaType: 'movie',
    tmdbId: 13,
    title: 'Forrest Gump',
    posterPath: '/arw2vcBveWOVZr6pxd9XTd1TdQa.jpg',
    stars: 5,
    lastWatchedAt: _daysAgo(180),
  ),
];

// ─────────────────────────────────────────────────────────────────────
// Taste profile (used by Home filter + Profile insights)
// ─────────────────────────────────────────────────────────────────────

final Map<String, dynamic> demoTasteProfile = {
  'combined': {
    'top_genres': [
      {'genre': 'Drama', 'weight': 0.28},
      {'genre': 'Thriller', 'weight': 0.22},
      {'genre': 'Crime', 'weight': 0.16},
      {'genre': 'Sci-Fi & Fantasy', 'weight': 0.14},
      {'genre': 'Comedy', 'weight': 0.12},
    ],
    'compatibility': {'within_1_star_pct': 0.78},
  },
  'per_user_solo': {
    kDemoUid: {
      'top_genres': [
        {'genre': 'Thriller', 'weight': 0.32},
        {'genre': 'Science Fiction', 'weight': 0.24},
        {'genre': 'Crime', 'weight': 0.18},
      ],
    },
    kDemoPartnerUid: {
      'top_genres': [
        {'genre': 'Drama', 'weight': 0.34},
        {'genre': 'Romance', 'weight': 0.21},
        {'genre': 'Comedy', 'weight': 0.17},
      ],
    },
  },
  'per_user_together': {
    kDemoUid: {
      'top_genres': [
        {'genre': 'Drama', 'weight': 0.30},
        {'genre': 'Thriller', 'weight': 0.24},
      ],
    },
    kDemoPartnerUid: {
      'top_genres': [
        {'genre': 'Drama', 'weight': 0.32},
        {'genre': 'Thriller', 'weight': 0.20},
      ],
    },
  },
};
