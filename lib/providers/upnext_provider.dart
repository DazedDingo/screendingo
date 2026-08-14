import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/watch_entry.dart';
import '../models/watchlist_item.dart';
import 'tmdb_provider.dart';
import 'watch_entries_provider.dart';
import 'watchlist_provider.dart';

/// One row in the "Up next" Home surface — the next episode of a show
/// the household is mid-watch on or has saved to the watchlist, due
/// within the visibility window.
class UpNextEpisode {
  final int tmdbId;
  final String showTitle;
  final String? showPosterPath;
  final int season;
  final int number;
  final String? episodeName;
  final DateTime airDate;

  /// Days from today to the air date. 0 = airs today, 1 = tomorrow,
  /// negative = aired in the recent past (still surfaces while within
  /// `kUpNextRecentDays` so a "just dropped" episode doesn't disappear
  /// the moment its date passes).
  final int daysUntilAir;

  const UpNextEpisode({
    required this.tmdbId,
    required this.showTitle,
    this.showPosterPath,
    required this.season,
    required this.number,
    this.episodeName,
    required this.airDate,
    required this.daysUntilAir,
  });

  String get key => 'tv:$tmdbId';

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'showTitle': showTitle,
        'showPosterPath': showPosterPath,
        'season': season,
        'number': number,
        'episodeName': episodeName,
        'airDate': airDate.toIso8601String(),
        'daysUntilAir': daysUntilAir,
      };

  factory UpNextEpisode.fromJson(Map<String, dynamic> json) => UpNextEpisode(
        tmdbId: (json['tmdbId'] as num).toInt(),
        showTitle: json['showTitle'] as String? ?? '',
        showPosterPath: json['showPosterPath'] as String?,
        season: (json['season'] as num?)?.toInt() ?? 0,
        number: (json['number'] as num?)?.toInt() ?? 0,
        episodeName: json['episodeName'] as String?,
        airDate: DateTime.parse(json['airDate'] as String),
        daysUntilAir: (json['daysUntilAir'] as num).toInt(),
      );
}

/// How many days into the future to surface upcoming episodes. Tight on
/// purpose — a 7-day horizon keeps the row tied to "this week" so it
/// only renders when there's something genuinely actionable.
const int kUpNextWindowDays = 7;

/// How many days in the recent past to keep an episode surfaced after
/// its air date. Short grace so an episode that aired today/yesterday
/// doesn't vanish before the household has watched it.
const int kUpNextRecentDays = 1;

/// Maximum tiles the Home row will render. Capped low because the whole
/// rationale for this surface is "low clutter, only when relevant" — a
/// long list defeats that. Households with more in-progress shows just
/// see the soonest-airing.
const int kUpNextMaxTiles = 3;

/// SharedPreferences key for the disk-backed cache of the most recent
/// successful Up Next computation. Persists across app launches so the
/// row renders instantly on cold start instead of waiting on the per-
/// show TMDB fan-out.
const String kUpNextCacheKey = 'wn_upnext_cache';

// Disk cache helper — load returns null on absent OR malformed JSON so
// a corrupted entry (version mismatch, partial write) silently drops
// instead of crashing the row on cold start.
class _UpNextDiskCache {
  static List<UpNextEpisode>? load(SharedPreferences prefs) {
    final raw = prefs.getString(kUpNextCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => UpNextEpisode.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      developer.log('Up Next cache corrupt, dropping: $e', name: 'upnext');
      return null;
    }
  }

  static Future<void> save(
    SharedPreferences prefs,
    List<UpNextEpisode> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(kUpNextCacheKey, encoded);
  }
}

/// Distinct TMDB ids of the TV shows eligible for Up Next: every show
/// the household is mid-watch on (`inProgressStatus == 'watching'` — the
/// same signal Library → Watching uses), plus TV shows saved to the
/// mode-visible watchlist. A watchlist show is skipped when the
/// household is already done with it — a watch entry marked
/// completed/dropped, or watched by either member (household-level
/// "seen", mirroring `watchedKeysProvider`'s shared-Trakt rationale).
/// Shows in both sources dedupe to one id.
List<int> upNextEligibleTvIds(
  List<WatchEntry> entries,
  List<WatchlistItem> watchlist,
) {
  final ids = <int>{};
  final finished = <int>{};
  for (final e in entries) {
    if (e.mediaType != 'tv') continue;
    if (e.inProgressStatus == 'watching') {
      ids.add(e.tmdbId);
    } else if (e.inProgressStatus == 'completed' ||
        e.inProgressStatus == 'dropped' ||
        e.watchedBy.values.any((v) => v)) {
      finished.add(e.tmdbId);
    }
  }
  for (final w in watchlist) {
    if (w.mediaType != 'tv') continue;
    if (finished.contains(w.tmdbId)) continue;
    ids.add(w.tmdbId);
  }
  return ids.toList();
}

/// Resolves the next episode for every TV show the household is
/// currently mid-watch on OR has saved to the watchlist, filters to
/// those with an air date inside the visibility window, and ranks by
/// soonest-airing.
///
/// Sources (see [upNextEligibleTvIds]): `WatchEntry.inProgressStatus ==
/// 'watching'` plus mode-visible watchlist TV rows — saving a show is
/// enough to surface its premiere/next episode; the user doesn't have to
/// mark it as watching first. Returns empty when neither source has an
/// eligible show; the Home row collapses to nothing in that case so the
/// screen stays the same as today.
// Stream-based stale-while-revalidate: yields the disk cache (if any)
// first so the row paints immediately on cold start, then fans the
// per-show TMDB calls and yields fresh data. Without this, the FIRST
// app open after install/relaunch waited 1-2s on the TMDB fan-out and
// the row visibly "popped in".
final upNextProvider =
    StreamProvider<List<UpNextEpisode>>((ref) async* {
  final prefs = await SharedPreferences.getInstance();
  final cached = _UpNextDiskCache.load(prefs);
  if (cached != null) yield cached;

  // Wait for BOTH Firestore streams to actually emit before making any
  // eligibility decision. Returning early keeps the cached yield as the
  // stream's last value until the first emits land. The watchlist gate
  // watches the raw stream (for the emitted-yet signal) while the list
  // itself comes from visibleWatchlistProvider so Solo/Together scope
  // rules stay defined in exactly one place.
  final entriesAsync = ref.watch(watchEntriesProvider);
  final watchlistAsync = ref.watch(watchlistProvider);
  if (entriesAsync.value == null || watchlistAsync.value == null) return;
  final entries = entriesAsync.value!;
  final watchlist = ref.watch(visibleWatchlistProvider);
  final tvIds = upNextEligibleTvIds(entries, watchlist);
  if (tvIds.isEmpty) {
    // Empty eligibility is ambiguous on cold start: it can mean
    // "household has finished everything" OR "Firestore just emitted
    // its initial empty snapshot before the server payload arrives."
    // We can't tell them apart at this point. Bias toward keeping the
    // cached row visible — only yield/save empty when we don't have a
    // non-empty cache to fall back to. The next Firestore emit
    // will (probably) carry the real data and re-trigger the stream
    // with the non-empty branch, which writes through authoritatively.
    if (cached == null || cached.isEmpty) {
      await _UpNextDiskCache.save(prefs, const []);
      yield const [];
    }
    return;
  }

  final tmdb = ref.watch(tmdbServiceProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final fetches = tvIds.map((tmdbId) async {
    try {
      final show = await tmdb.tvShow(tmdbId);
      final next = show['next_episode_to_air'] as Map<String, dynamic>?;
      if (next == null) return null;
      final airDateStr = next['air_date'] as String?;
      if (airDateStr == null || airDateStr.isEmpty) return null;
      final parsed = DateTime.tryParse(airDateStr);
      if (parsed == null) return null;
      final airDate = DateTime(parsed.year, parsed.month, parsed.day);
      final daysUntil = airDate.difference(today).inDays;
      if (daysUntil < -kUpNextRecentDays || daysUntil > kUpNextWindowDays) {
        return null;
      }
      return UpNextEpisode(
        tmdbId: tmdbId,
        showTitle: (show['name'] as String?) ?? '',
        showPosterPath: show['poster_path'] as String?,
        season: (next['season_number'] as num?)?.toInt() ?? 0,
        number: (next['episode_number'] as num?)?.toInt() ?? 0,
        episodeName: next['name'] as String?,
        airDate: airDate,
        daysUntilAir: daysUntil,
      );
    } catch (_) {
      // A single show's TMDB lookup failing shouldn't sink the row —
      // skip it and let other shows surface.
      return null;
    }
  }).toList();

  final results = await Future.wait(fetches);
  final fresh = results.whereType<UpNextEpisode>().toList()
    ..sort((a, b) => a.airDate.compareTo(b.airDate));
  final capped = fresh.take(kUpNextMaxTiles).toList();
  await _UpNextDiskCache.save(prefs, capped);
  yield capped;
});

/// Lightweight summary used by Profile → Insights as a "feature health"
/// line. Reports the total tracked TV count (in-progress + eligible
/// watchlist shows, deduped — same [upNextEligibleTvIds] source the Home
/// row uses) + the closest upcoming episode (so the user can
/// sanity-check that the Home row's silence reflects "nothing
/// scheduled" rather than "feature broken").
class UpNextSummary {
  final int trackedShowCount;
  final UpNextEpisode? next;

  const UpNextSummary({required this.trackedShowCount, this.next});
}

final upNextSummaryProvider =
    FutureProvider.autoDispose<UpNextSummary>((ref) async {
  final entriesAsync = ref.watch(watchEntriesProvider);
  final entries = entriesAsync.value ?? const <WatchEntry>[];
  final watchlist = ref.watch(visibleWatchlistProvider);
  final trackedCount = upNextEligibleTvIds(entries, watchlist).length;
  final upcoming = await ref.watch(upNextProvider.future);
  return UpNextSummary(
    trackedShowCount: trackedCount,
    next: upcoming.isEmpty ? null : upcoming.first,
  );
});
