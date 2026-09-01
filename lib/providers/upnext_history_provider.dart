import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tmdb_provider.dart';
import 'trakt_provider.dart';
import 'up_next_lag_provider.dart';
import 'upnext_provider.dart';
import 'watch_entries_provider.dart';
import 'watchlist_provider.dart';

/// How many days into the past "Recently aired" looks back. A household
/// that doesn't open the app for a few days should still be able to see
/// what dropped — 14 days is a generous-but-bounded lookback so the list
/// doesn't grow unbounded for shows that have been mid-watch for months.
const int kUpNextHistoryDays = 14;

/// Per-show cap on how many recently-aired episodes render. A show that
/// dumped a whole season inside the window shouldn't crowd out every
/// other tracked show.
const int kUpNextHistoryMaxPerShow = 10;

/// One row in the "Recently aired" history screen — an episode of a
/// tracked show that became available within the last
/// [kUpNextHistoryDays] days.
class UpNextHistoryEntry {
  final int tmdbId;
  final String showTitle;
  final String? showPosterPath;
  final int season;
  final int number;
  final String? episodeName;
  final String? stillPath;

  /// The moment the episode is actually expected to have been watchable —
  /// same `availableAt` contract as [UpNextEpisode]: Trakt `first_aired` +
  /// lag when resolved, else the TMDB date-only `air_date` at local
  /// midnight.
  final DateTime availableAt;

  /// True when [availableAt] came from a real Trakt-resolved air time
  /// rather than the date-only fallback.
  final bool hasAirTime;

  const UpNextHistoryEntry({
    required this.tmdbId,
    required this.showTitle,
    this.showPosterPath,
    required this.season,
    required this.number,
    this.episodeName,
    this.stillPath,
    required this.availableAt,
    required this.hasAirTime,
  });
}

/// Parses a TMDB episode map's `air_date` into a local-midnight
/// [DateTime]. Returns null when the field is missing/unparseable.
DateTime? _episodeAirDate(Map<String, dynamic> episode) {
  final airDateStr = episode['air_date'] as String?;
  if (airDateStr == null || airDateStr.isEmpty) return null;
  final parsed = DateTime.tryParse(airDateStr);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// True when [availableAt] falls inside the history window: became
/// available after [cutoff] but not later than [now]. Future episodes
/// (the Up Next row's job, not history's) are excluded by the
/// `!isAfter(now)` half; anything older than the lookback is excluded by
/// the `isAfter(cutoff)` half.
bool _inHistoryWindow(DateTime availableAt, DateTime cutoff, DateTime now) {
  return availableAt.isAfter(cutoff) && !availableAt.isAfter(now);
}

/// Episodes of tracked shows that became available in the last
/// [kUpNextHistoryDays] days — the "Recently aired" history screen. Reuses
/// the same eligibility rules ([upNextEligibleTvIds]) and Trakt real-air-
/// time pipeline as [upNextProvider] (gotcha 52), including the shared
/// on-disk tmdbId→traktId cache ([loadTraktIdCache] / [saveTraktIdCache]).
///
/// Per eligible show: reads `last_episode_to_air` off a lean `/tv/{id}`
/// call; if that episode's resolved `availableAt` is already older than
/// the lookback window, the show contributes nothing and — importantly —
/// the season fetch is skipped entirely (no point paying for it). Only
/// once the show clears that bar do we fetch the full season
/// (`tmdb.tvSeason`) and resolve every episode up to and including the
/// last-aired one, keeping only the ones that actually fall inside the
/// window.
///
/// Known limitation: episodes from the *previous* season that fell inside
/// the window are not fetched — only the season containing
/// `last_episode_to_air` is queried. A season premiere just after a mid-
/// season finale could theoretically miss a stray in-window episode from
/// the prior season; deemed an acceptable trade-off against doubling the
/// per-show TMDB fan-out.
///
/// A single show's TMDB/Trakt failure never sinks the others — each
/// show's fetch is wrapped in try/catch and degrades to an empty list on
/// error; Trakt failures specifically degrade to the date-only fallback
/// rather than dropping the episode (mirrors [upNextProvider]).
final upNextHistoryProvider =
    FutureProvider.autoDispose<List<UpNextHistoryEntry>>((ref) async {
  final entriesAsync = ref.watch(watchEntriesProvider);
  final entries = entriesAsync.value ?? const [];
  final watchlist = ref.watch(visibleWatchlistProvider);
  final tvIds = upNextEligibleTvIds(entries, watchlist);
  if (tvIds.isEmpty) return const [];

  final tmdb = ref.watch(tmdbServiceProvider);
  final trakt = ref.watch(traktServiceProvider);
  final lagHours = ref.watch(upNextLagHoursProvider);
  final now = DateTime.now();
  final cutoff = now.subtract(const Duration(days: kUpNextHistoryDays));

  final prefs = await SharedPreferences.getInstance();
  final traktIdCache = loadTraktIdCache(prefs);
  var traktIdCacheDirty = false;

  Future<int?> resolveTraktShowId(int tmdbId) async {
    if (traktIdCache.containsKey(tmdbId)) return traktIdCache[tmdbId];
    final resolved = await trakt.lookupShowTraktId(tmdbId);
    if (resolved != null) {
      traktIdCache[tmdbId] = resolved;
      traktIdCacheDirty = true;
    }
    return resolved;
  }

  Future<DateTime?> resolveAirsAtUtc(
    int tmdbId,
    int season,
    int number,
  ) async {
    try {
      final traktShowId = await resolveTraktShowId(tmdbId);
      if (traktShowId == null) return null;
      return await trakt.fetchEpisodeFirstAired(
        traktShowId: traktShowId,
        season: season,
        number: number,
      );
    } catch (_) {
      // Trakt failing for this episode just means no real air time — the
      // caller falls back to the date-only availableAt.
      return null;
    }
  }

  DateTime resolveAvailableAt(DateTime airDate, DateTime? airsAtUtc) {
    return airsAtUtc != null
        ? airsAtUtc.add(Duration(hours: lagHours)).toLocal()
        : airDate;
  }

  final fetches = tvIds.map((tmdbId) async {
    try {
      final show = await tmdb.tvShow(tmdbId);
      final lastRaw = show['last_episode_to_air'];
      if (lastRaw is! Map) return const <UpNextHistoryEntry>[];
      final last = Map<String, dynamic>.from(lastRaw);
      final lastAirDate = _episodeAirDate(last);
      if (lastAirDate == null) return const <UpNextHistoryEntry>[];
      final lastSeason = (last['season_number'] as num?)?.toInt() ?? 0;
      final lastNumber = (last['episode_number'] as num?)?.toInt() ?? 0;

      final lastAirsAtUtc =
          await resolveAirsAtUtc(tmdbId, lastSeason, lastNumber);
      final lastAvailableAt = resolveAvailableAt(lastAirDate, lastAirsAtUtc);
      if (!lastAvailableAt.isAfter(cutoff)) {
        // Nothing recent for this show — skip the season fetch entirely.
        return const <UpNextHistoryEntry>[];
      }

      final season = await tmdb.tvSeason(tmdbId, lastSeason);
      final episodesRaw = season['episodes'];
      if (episodesRaw is! List) return const <UpNextHistoryEntry>[];

      final showTitle = (show['name'] as String?) ?? '';
      final showPosterPath = show['poster_path'] as String?;

      final results = <UpNextHistoryEntry>[];
      for (final epRaw in episodesRaw) {
        if (epRaw is! Map) continue;
        final ep = Map<String, dynamic>.from(epRaw);
        final epNumber = (ep['episode_number'] as num?)?.toInt() ?? 0;
        if (epNumber > lastNumber) continue;
        final epAirDate = _episodeAirDate(ep);
        if (epAirDate == null) continue;
        final epAirsAtUtc =
            await resolveAirsAtUtc(tmdbId, lastSeason, epNumber);
        final availableAt = resolveAvailableAt(epAirDate, epAirsAtUtc);
        if (!_inHistoryWindow(availableAt, cutoff, now)) continue;
        results.add(UpNextHistoryEntry(
          tmdbId: tmdbId,
          showTitle: showTitle,
          showPosterPath: showPosterPath,
          season: lastSeason,
          number: epNumber,
          episodeName: ep['name'] as String?,
          stillPath: ep['still_path'] as String?,
          availableAt: availableAt,
          hasAirTime: epAirsAtUtc != null,
        ));
      }
      results.sort((a, b) => b.availableAt.compareTo(a.availableAt));
      return results.take(kUpNextHistoryMaxPerShow).toList();
    } catch (_) {
      // A single show's TMDB lookup failing shouldn't sink the screen —
      // skip it and let other shows surface.
      return const <UpNextHistoryEntry>[];
    }
  }).toList();

  final results = await Future.wait(fetches);
  if (traktIdCacheDirty) {
    await saveTraktIdCache(prefs, traktIdCache);
  }
  return results.expand((e) => e).toList()
    ..sort((a, b) => b.availableAt.compareTo(a.availableAt));
});

const List<String> _kWeekdayAbbr = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _kMonthAbbr = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Day-group header label for the history screen: 'Today' / 'Yesterday' /
/// 'Thu 28 Aug' (weekday + day + short month, no year — manual arrays, no
/// `intl` dependency). Compares calendar days, not 24h windows.
String historyDayLabel(DateTime day, DateTime today) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = d.difference(t).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  final weekday = _kWeekdayAbbr[d.weekday - 1];
  final month = _kMonthAbbr[d.month - 1];
  return '$weekday ${d.day} $month';
}

/// Groups history entries by the local calendar day of [UpNextHistoryEntry
/// .availableAt], days descending (most recent day first), entries within
/// a day also descending (most recent first).
List<MapEntry<DateTime, List<UpNextHistoryEntry>>> groupHistoryByDay(
  List<UpNextHistoryEntry> entries,
) {
  final byDay = <DateTime, List<UpNextHistoryEntry>>{};
  for (final e in entries) {
    final local = e.availableAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(e);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      MapEntry(
        day,
        byDay[day]!..sort((a, b) => b.availableAt.compareTo(a.availableAt)),
      ),
  ];
}
