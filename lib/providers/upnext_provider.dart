import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/watch_entry.dart';
import '../models/watchlist_item.dart';
import 'tmdb_provider.dart';
import 'trakt_provider.dart';
import 'up_next_lag_provider.dart';
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

  /// Date-only air date as reported by TMDB (network's local calendar
  /// date — see the shared spec's Problem section). Kept for back-compat
  /// and as the ultimate fallback when Trakt has no real air time.
  final DateTime airDate;

  /// The moment the episode is actually expected to be watchable:
  /// `airsAtUtc + lag` when Trakt resolved a real air time, else
  /// `airDate` at local midnight (today's date-only behaviour).
  final DateTime availableAt;

  /// Real broadcast instant (UTC) from Trakt's `first_aired`, or null
  /// when Trakt couldn't resolve one (unlinked show, network error,
  /// missing field) — in which case the row falls back to date-only.
  final DateTime? airsAtUtc;

  /// True when a real Trakt air time was resolved for this episode.
  bool get hasAirTime => airsAtUtc != null;

  /// Days from today to [availableAt]'s calendar date — "days until
  /// available". 0 = available today, 1 = tomorrow, negative = became
  /// available in the recent past (still surfaces while within
  /// `kUpNextRecentDays` so a "just dropped" episode doesn't disappear
  /// the moment its date passes).
  final int daysUntilAir;

  UpNextEpisode({
    required this.tmdbId,
    required this.showTitle,
    this.showPosterPath,
    required this.season,
    required this.number,
    this.episodeName,
    required this.airDate,
    DateTime? availableAt,
    this.airsAtUtc,
    required this.daysUntilAir,
  }) : availableAt = availableAt ?? airDate;

  String get key => 'tv:$tmdbId';

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'showTitle': showTitle,
        'showPosterPath': showPosterPath,
        'season': season,
        'number': number,
        'episodeName': episodeName,
        'airDate': airDate.toIso8601String(),
        'availableAt': availableAt.toIso8601String(),
        'airsAtUtc': airsAtUtc?.toIso8601String(),
        'daysUntilAir': daysUntilAir,
      };

  factory UpNextEpisode.fromJson(Map<String, dynamic> json) {
    final airDate = DateTime.parse(json['airDate'] as String);
    final availableAtRaw = json['availableAt'] as String?;
    final airsAtUtcRaw = json['airsAtUtc'] as String?;
    return UpNextEpisode(
      tmdbId: (json['tmdbId'] as num).toInt(),
      showTitle: json['showTitle'] as String? ?? '',
      showPosterPath: json['showPosterPath'] as String?,
      season: (json['season'] as num?)?.toInt() ?? 0,
      number: (json['number'] as num?)?.toInt() ?? 0,
      episodeName: json['episodeName'] as String?,
      airDate: airDate,
      // Old on-disk cache entries predate these fields — tolerate their
      // absence by falling back to the pre-Trakt date-only shape.
      availableAt:
          availableAtRaw != null ? DateTime.parse(availableAtRaw) : airDate,
      airsAtUtc: airsAtUtcRaw != null ? DateTime.parse(airsAtUtcRaw) : null,
      daysUntilAir: (json['daysUntilAir'] as num).toInt(),
    );
  }
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

/// Pulls the up-to-two raw episode candidates off a TMDB `/tv/{id}`
/// payload — `last_episode_to_air` and `next_episode_to_air` — dropping
/// nulls and deduping by `(season_number, episode_number)` (a show whose
/// last-aired and next-to-air happen to be the same episode — TMDB does
/// this right after an episode airs — should only be evaluated once).
List<Map<String, dynamic>> upNextCandidates(Map<String, dynamic> show) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final key in const ['last_episode_to_air', 'next_episode_to_air']) {
    final raw = show[key];
    if (raw is! Map) continue;
    final ep = Map<String, dynamic>.from(raw);
    final season = (ep['season_number'] as num?)?.toInt() ?? 0;
    final number = (ep['episode_number'] as num?)?.toInt() ?? 0;
    final dedupeKey = '$season:$number';
    if (!seen.add(dedupeKey)) continue;
    out.add(ep);
  }
  return out;
}

/// Builds an [UpNextEpisode] from one candidate episode map (see
/// [upNextCandidates]), applying the shared spec's availableAt / lag /
/// window-filter steps. Returns null when the candidate has no usable
/// air date, or its resolved `availableAt` falls outside
/// `[-kUpNextRecentDays, kUpNextWindowDays]`.
///
/// [airsAtUtc] is the real broadcast instant resolved from Trakt (or null
/// when unresolved) — when present, `availableAt = airsAtUtc + lagHours`;
/// otherwise `availableAt` falls back to the TMDB date-only `air_date` at
/// local midnight, matching the pre-Trakt behaviour.
UpNextEpisode? buildUpNextEpisode({
  required int tmdbId,
  required Map<String, dynamic> show,
  required Map<String, dynamic> episode,
  DateTime? airsAtUtc,
  required int lagHours,
  required DateTime now,
}) {
  final airDateStr = episode['air_date'] as String?;
  if (airDateStr == null || airDateStr.isEmpty) return null;
  final parsedAirDate = DateTime.tryParse(airDateStr);
  if (parsedAirDate == null) return null;
  final airDate = DateTime(parsedAirDate.year, parsedAirDate.month, parsedAirDate.day);

  final availableAt = airsAtUtc != null
      ? airsAtUtc.add(Duration(hours: lagHours)).toLocal()
      : airDate;

  // Calendar-day difference. Built with `DateTime.utc` on purpose: local
  // midnights straddling a DST change are 23h/25h apart and `inDays`
  // truncates 23h to 0, which would mislabel "tomorrow" as "today" twice
  // a year. UTC days are always exactly 24h.
  final today = DateTime.utc(now.year, now.month, now.day);
  final availableDate =
      DateTime.utc(availableAt.year, availableAt.month, availableAt.day);
  final daysUntilAir = availableDate.difference(today).inDays;
  if (daysUntilAir < -kUpNextRecentDays || daysUntilAir > kUpNextWindowDays) {
    return null;
  }

  return UpNextEpisode(
    tmdbId: tmdbId,
    showTitle: (show['name'] as String?) ?? '',
    showPosterPath: show['poster_path'] as String?,
    season: (episode['season_number'] as num?)?.toInt() ?? 0,
    number: (episode['episode_number'] as num?)?.toInt() ?? 0,
    episodeName: episode['name'] as String?,
    airDate: airDate,
    availableAt: availableAt,
    airsAtUtc: airsAtUtc,
    daysUntilAir: daysUntilAir,
  );
}

/// SharedPreferences key for the tmdbId→traktId lookup cache. A show's
/// Trakt id never changes, so once resolved we never need to hit Trakt's
/// `/search/tmdb` endpoint for it again.
const String kUpNextTraktIdCacheKey = 'wn_trakt_show_ids';

Map<int, int> _loadTraktIdCache(SharedPreferences prefs) {
  final raw = prefs.getString(kUpNextTraktIdCacheKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final out = <int, int>{};
    decoded.forEach((k, v) {
      final tmdbId = int.tryParse(k.toString());
      final traktId = v is num ? v.toInt() : null;
      if (tmdbId != null && traktId != null) out[tmdbId] = traktId;
    });
    return out;
  } catch (e) {
    developer.log('Trakt id cache corrupt, dropping: $e', name: 'upnext');
    return {};
  }
}

Future<void> _saveTraktIdCache(
  SharedPreferences prefs,
  Map<int, int> cache,
) async {
  final encoded =
      jsonEncode(cache.map((k, v) => MapEntry(k.toString(), v)));
  await prefs.setString(kUpNextTraktIdCacheKey, encoded);
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
///
/// Real air time: for each candidate episode ([upNextCandidates]) we
/// resolve the Trakt show id (cached — see [kUpNextTraktIdCacheKey]) then
/// fetch the episode's real `first_aired` via Trakt's public API, and
/// build the row via [buildUpNextEpisode] using the user's configured
/// lag ([upNextLagHoursProvider]). Any Trakt failure (unresolved id,
/// non-200, network error) degrades to the TMDB date-only fallback —
/// never drops the row. Per show, the candidate with the earliest
/// `availableAt` wins (spec step 4) so a just-available episode stays on
/// screen even after TMDB has already advanced `next_episode_to_air`.
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
  final trakt = ref.watch(traktServiceProvider);
  final lagHours = ref.watch(upNextLagHoursProvider);
  final now = DateTime.now();

  final traktIdCache = _loadTraktIdCache(prefs);
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

  final fetches = tvIds.map((tmdbId) async {
    try {
      final show = await tmdb.tvShow(tmdbId);
      final candidates = upNextCandidates(show);
      if (candidates.isEmpty) return null;

      UpNextEpisode? best;
      for (final episode in candidates) {
        DateTime? airsAtUtc;
        try {
          final traktShowId = await resolveTraktShowId(tmdbId);
          if (traktShowId != null) {
            final season = (episode['season_number'] as num?)?.toInt() ?? 0;
            final number = (episode['episode_number'] as num?)?.toInt() ?? 0;
            airsAtUtc = await trakt.fetchEpisodeFirstAired(
              traktShowId: traktShowId,
              season: season,
              number: number,
            );
          }
        } catch (_) {
          // Trakt failing for this episode just means no real air time —
          // buildUpNextEpisode falls back to the date-only behaviour.
          airsAtUtc = null;
        }
        final built = buildUpNextEpisode(
          tmdbId: tmdbId,
          show: show,
          episode: episode,
          airsAtUtc: airsAtUtc,
          lagHours: lagHours,
          now: now,
        );
        if (built == null) continue;
        if (best == null || built.availableAt.isBefore(best.availableAt)) {
          best = built;
        }
      }
      return best;
    } catch (_) {
      // A single show's TMDB lookup failing shouldn't sink the row —
      // skip it and let other shows surface.
      return null;
    }
  }).toList();

  final results = await Future.wait(fetches);
  if (traktIdCacheDirty) {
    await _saveTraktIdCache(prefs, traktIdCache);
  }
  final fresh = results.whereType<UpNextEpisode>().toList()
    ..sort((a, b) => a.availableAt.compareTo(b.availableAt));
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
