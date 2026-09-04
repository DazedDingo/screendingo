import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/trakt_season_air_cache.dart';
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

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'showTitle': showTitle,
        'showPosterPath': showPosterPath,
        'season': season,
        'number': number,
        'episodeName': episodeName,
        'stillPath': stillPath,
        'availableAt': availableAt.toIso8601String(),
        'hasAirTime': hasAirTime,
      };

  factory UpNextHistoryEntry.fromJson(Map<String, dynamic> json) {
    return UpNextHistoryEntry(
      tmdbId: (json['tmdbId'] as num).toInt(),
      showTitle: json['showTitle'] as String? ?? '',
      showPosterPath: json['showPosterPath'] as String?,
      season: (json['season'] as num?)?.toInt() ?? 0,
      number: (json['number'] as num?)?.toInt() ?? 0,
      episodeName: json['episodeName'] as String?,
      stillPath: json['stillPath'] as String?,
      availableAt: DateTime.parse(json['availableAt'] as String),
      hasAirTime: json['hasAirTime'] as bool? ?? false,
    );
  }
}

/// SharedPreferences key for the disk-backed cache of the most recent
/// successful "Recently aired" computation — mirrors
/// `upnext_provider.dart`'s `kUpNextCacheKey` so the history screen also
/// paints instantly from a stale-while-revalidate cache instead of a
/// blank loading spinner on every visit.
const String kUpNextHistoryCacheKey = 'wn_upnext_history_cache';

class _UpNextHistoryDiskCache {
  static List<UpNextHistoryEntry>? load(SharedPreferences prefs) {
    final raw = prefs.getString(kUpNextHistoryCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) =>
              UpNextHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      developer.log('Up Next history cache corrupt, dropping: $e',
          name: 'upnext');
      return null;
    }
  }

  static Future<void> save(
    SharedPreferences prefs,
    List<UpNextHistoryEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(kUpNextHistoryCacheKey, encoded);
  }
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
/// on-disk tmdbId→traktId cache ([loadTraktIdCache] / [saveTraktIdCache])
/// AND the shared season air-time cache (`TraktSeasonAirCache`) — a
/// season resolved by the Home row (or vice versa) is free here for the
/// rest of its 6h TTL, and this provider's own resolution warms the cache
/// for the others in turn.
///
/// Stale-while-revalidate, mirroring [upNextProvider]'s stream shape:
/// yields the on-disk cache first (if any) so the screen paints
/// instantly, then computes fresh and yields again once the fan-out
/// completes.
///
/// Per eligible show: reads `last_episode_to_air` off a lean `/tv/{id}`
/// call; if that episode's resolved `availableAt` is already older than
/// the lookback window, the show contributes nothing and — importantly —
/// the season fetch is skipped entirely (no point paying for it). Only
/// once the show clears that bar do we fetch the full season
/// (`tmdb.tvSeason`, for episode name/still_path display metadata — TMDB
/// is free, gotcha "operating cost") and resolve every episode up to and
/// including the last-aired one, keeping only the ones that actually fall
/// inside the window. Episode DATES come from the ONE Trakt season call
/// per show (`resolveSeasonMap`/`TraktSeasonAirCache`), not a per-episode
/// Trakt call — that's the whole point of the season-level cache.
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
    StreamProvider.autoDispose<List<UpNextHistoryEntry>>((ref) async* {
  final prefs = await SharedPreferences.getInstance();
  final cached = _UpNextHistoryDiskCache.load(prefs);
  if (cached != null) yield cached;

  // Wait for watchEntriesProvider to actually emit before deciding
  // eligibility — mirrors upNextProvider's guard (gotcha: a StreamProvider
  // that yields on a still-loading dependency settles its AsyncValue
  // prematurely with the wrong "empty" answer; returning without yielding
  // keeps this generation in the loading state until the real Firestore
  // snapshot lands and triggers a fresh generator run via `ref.watch`).
  final entriesAsync = ref.watch(watchEntriesProvider);
  if (entriesAsync.value == null) return;
  final entries = entriesAsync.value!;
  final watchlist = ref.watch(visibleWatchlistProvider);
  final tvIds = upNextEligibleTvIds(entries, watchlist);
  if (tvIds.isEmpty) {
    if (cached == null || cached.isEmpty) {
      const empty = <UpNextHistoryEntry>[];
      await _UpNextHistoryDiskCache.save(prefs, empty);
      yield empty;
    }
    return;
  }

  final tmdb = ref.watch(tmdbServiceProvider);
  final trakt = ref.watch(traktServiceProvider);
  final lagHours = ref.watch(upNextLagHoursProvider);
  final now = DateTime.now();
  final cutoff = now.subtract(const Duration(days: kUpNextHistoryDays));

  final traktIdCache = loadTraktIdCache(prefs);
  var traktIdCacheDirty = false;
  final seasonAirCache = TraktSeasonAirCache(prefs);
  final seasonMemo = <String, Map<int, DateTime?>?>{};

  Future<int?> resolveTraktShowId(int tmdbId) async {
    if (traktIdCache.containsKey(tmdbId)) return traktIdCache[tmdbId];
    final resolved = await trakt.lookupShowTraktId(tmdbId);
    if (resolved != null) {
      traktIdCache[tmdbId] = resolved;
      traktIdCacheDirty = true;
    }
    return resolved;
  }

  Future<Map<int, DateTime?>?> resolveSeasonMap(
    int traktShowId,
    int season,
  ) async {
    final memoKey = '$traktShowId:$season';
    if (seasonMemo.containsKey(memoKey)) return seasonMemo[memoKey];
    final fromDisk = seasonAirCache.get(traktShowId, season, now);
    if (fromDisk != null) {
      seasonMemo[memoKey] = fromDisk;
      return fromDisk;
    }
    try {
      final fetched = await trakt.fetchSeasonFirstAired(
        traktShowId: traktShowId,
        season: season,
      );
      if (fetched != null) {
        seasonAirCache.put(traktShowId, season, fetched, now);
      }
      seasonMemo[memoKey] = fetched;
      return fetched;
    } catch (_) {
      seasonMemo[memoKey] = null;
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

      final traktShowId = await resolveTraktShowId(tmdbId);
      final seasonMap = traktShowId != null
          ? await resolveSeasonMap(traktShowId, lastSeason)
          : null;

      final lastAirsAtUtc = seasonMap?[lastNumber];
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
        final epAirsAtUtc = seasonMap?[epNumber];
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
  await seasonAirCache.save();
  final fresh = results.expand((e) => e).toList()
    ..sort((a, b) => b.availableAt.compareTo(a.availableAt));
  await _UpNextHistoryDiskCache.save(prefs, fresh);
  yield fresh;
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
