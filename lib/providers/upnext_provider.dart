import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/watch_entry.dart';
import '../models/watchlist_item.dart';
import '../utils/trakt_season_air_cache.dart';
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

/// Stream payload for [upNextProvider]: the (capped) forward-looking row
/// plus a lightweight backward-looking count used to keep the Home entry
/// point alive when nothing is currently airing soon.
class UpNextData {
  final List<UpNextEpisode> episodes;

  /// Total in-window (last [kUpNextRecentCountDays] days) recently-aired
  /// episode count across every eligible show — see
  /// [upNextProvider]'s doc comment. Independent of [episodes]: an
  /// episode that aired 3 days ago contributes here even though it fell
  /// out of the forward-looking row's `[-1, +7]` window.
  final int recentCount;

  const UpNextData({required this.episodes, this.recentCount = 0});

  Map<String, dynamic> toJson() => {
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'recentCount': recentCount,
      };
}

/// How many days into the future to surface upcoming episodes. Tight on
/// purpose — a 7-day horizon keeps the row tied to "this week" so it
/// only renders when there's something genuinely actionable.
const int kUpNextWindowDays = 7;

/// How many days in the recent past to keep an episode surfaced after
/// its air date. Short grace so an episode that aired today/yesterday
/// doesn't vanish before the household has watched it.
const int kUpNextRecentDays = 1;

/// Lookback window (days) for [UpNextData.recentCount] — how far back an
/// episode's `availableAt` can sit and still count toward "N recently
/// aired" on the Home chip. Mirrors [kUpNextWindowDays]'s forward horizon
/// so the two read as symmetric "this week, past and future" windows.
const int kUpNextRecentCountDays = 7;

/// Per-show cap on how many recently-aired episodes count toward
/// [UpNextData.recentCount]. Shares the value (and rationale — a show
/// that dumped a whole season shouldn't dominate the count) with
/// `kUpNextHistoryMaxPerShow` in `upnext_history_provider.dart`; kept as
/// its own constant here so this file has no dependency on that one.
const int kUpNextRecentCountMaxPerShow = 10;

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
// instead of crashing the row on cold start. Back-compat: the on-disk
// shape used to be a bare JSON array of episodes; that still parses,
// with recentCount defaulting to 0 (recomputed on the next fresh run).
class _UpNextDiskCache {
  static UpNextData? load(SharedPreferences prefs) {
    final raw = prefs.getString(kUpNextCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final episodes = decoded
            .whereType<Map>()
            .map((e) => UpNextEpisode.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return UpNextData(episodes: episodes, recentCount: 0);
      }
      if (decoded is Map) {
        final episodesRaw = decoded['episodes'];
        final episodes = (episodesRaw is List ? episodesRaw : const [])
            .whereType<Map>()
            .map((e) => UpNextEpisode.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final recentCount = (decoded['recentCount'] as num?)?.toInt() ?? 0;
        return UpNextData(episodes: episodes, recentCount: recentCount);
      }
      return null;
    } catch (e) {
      developer.log('Up Next cache corrupt, dropping: $e', name: 'upnext');
      return null;
    }
  }

  static Future<void> save(SharedPreferences prefs, UpNextData data) async {
    await prefs.setString(kUpNextCacheKey, jsonEncode(data.toJson()));
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

/// Parses a TMDB episode map's `air_date` into a local-midnight
/// [DateTime]. Returns null when the field is missing/unparseable.
DateTime? _episodeAirDate(Map<String, dynamic> episode) {
  final airDateStr = episode['air_date'] as String?;
  if (airDateStr == null || airDateStr.isEmpty) return null;
  final parsed = DateTime.tryParse(airDateStr);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
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

/// True when [availableAt] falls inside the trailing recent-count window:
/// became available within the last [kUpNextRecentCountDays] days, not
/// later than [now].
bool _inRecentCountWindow(DateTime availableAt, DateTime now) {
  final cutoff = now.subtract(const Duration(days: kUpNextRecentCountDays));
  return availableAt.isAfter(cutoff) && !availableAt.isAfter(now);
}

/// SharedPreferences key for the tmdbId→traktId lookup cache. A show's
/// Trakt id never changes, so once resolved we never need to hit Trakt's
/// `/search/tmdb` endpoint for it again.
const String kUpNextTraktIdCacheKey = 'wn_trakt_show_ids';

/// Loads the tmdbId→traktId lookup cache. Public — shared by
/// [upNextProvider] and `upNextHistoryProvider` (Recently Aired) so both
/// surfaces read/write one on-disk cache instead of maintaining separate
/// copies.
Map<int, int> loadTraktIdCache(SharedPreferences prefs) {
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

/// Saves the tmdbId→traktId lookup cache. Public — see [loadTraktIdCache].
Future<void> saveTraktIdCache(
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
/// mark it as watching first. Returns empty episodes when neither source
/// has an eligible show; the Home row collapses to nothing in that case
/// so the screen stays the same as today.
///
/// Real air time: for each candidate episode ([upNextCandidates]) we
/// resolve the Trakt show id (cached — see [kUpNextTraktIdCacheKey]) then
/// the SHOW-SEASON's air-time map — one Trakt call per (show, season),
/// cached on disk via [TraktSeasonAirCache] (6h TTL) and memoized within
/// a single provider run so the `last_episode_to_air` and
/// `next_episode_to_air` candidates sharing a season don't double-fetch —
/// then builds the row via [buildUpNextEpisode] using the user's
/// configured lag ([upNextLagHoursProvider]). Any Trakt failure
/// (unresolved id, non-200, network error) degrades to the TMDB
/// date-only fallback — never drops the row. Per show, the candidate
/// with the earliest `availableAt` wins (spec step 4) so a just-available
/// episode stays on screen even after TMDB has already advanced
/// `next_episode_to_air`.
///
/// [UpNextData.recentCount]: independently of the forward-looking row,
/// each eligible show also contributes its count of episodes whose
/// `availableAt` falls in `[now - kUpNextRecentCountDays, now]` — capped
/// per show at [kUpNextRecentCountMaxPerShow]. When the show's Trakt
/// season map resolved, every episode number up to and including
/// `last_episode_to_air`'s is checked (cheap: no extra Trakt call, reuses
/// the same season map fetched for the row above when the seasons match);
/// otherwise it falls back to counting just `last_episode_to_air` itself
/// via its date-only air date. This keeps the Home entry point alive
/// (as a "N recently aired" chip) even on weeks where the row itself is
/// empty because the last episode aired more than [kUpNextRecentDays]
/// days ago.
// Stream-based stale-while-revalidate: yields the disk cache (if any)
// first so the row paints immediately on cold start, then fans the
// per-show TMDB calls and yields fresh data. Without this, the FIRST
// app open after install/relaunch waited 1-2s on the TMDB fan-out and
// the row visibly "popped in".
final upNextProvider = StreamProvider<UpNextData>((ref) async* {
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
    if (cached == null || cached.episodes.isEmpty) {
      const empty = UpNextData(episodes: [], recentCount: 0);
      await _UpNextDiskCache.save(prefs, empty);
      yield empty;
    }
    return;
  }

  final tmdb = ref.watch(tmdbServiceProvider);
  final trakt = ref.watch(traktServiceProvider);
  final lagHours = ref.watch(upNextLagHoursProvider);
  final now = DateTime.now();

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

  // One Trakt call per (traktShowId, season) — checks the in-run memo
  // first (so two candidates in the same season within THIS run never
  // double-fetch), then the persistent 6h-TTL cache, then falls through
  // to a real Trakt fetch. Failures degrade to null (date-only fallback
  // upstream), never throw.
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

  final fetches = tvIds.map((tmdbId) async {
    Map<String, dynamic> show;
    try {
      show = await tmdb.tvShow(tmdbId);
    } catch (_) {
      // A single show's TMDB lookup failing shouldn't sink the row —
      // skip it and let other shows surface.
      return (null, 0);
    }

    // --- recentCount contribution for this show (independent of the
    // forward-looking row below) ---
    var showRecentCount = 0;
    try {
      final lastRaw = show['last_episode_to_air'];
      if (lastRaw is Map) {
        final last = Map<String, dynamic>.from(lastRaw);
        final lastAirDate = _episodeAirDate(last);
        final lastSeason = (last['season_number'] as num?)?.toInt() ?? 0;
        final lastNumber = (last['episode_number'] as num?)?.toInt() ?? 0;
        if (lastAirDate != null) {
          final traktShowId = await resolveTraktShowId(tmdbId);
          final seasonMap = traktShowId != null
              ? await resolveSeasonMap(traktShowId, lastSeason)
              : null;
          if (seasonMap != null) {
            final numbers = seasonMap.keys.where((n) => n <= lastNumber).toList()
              ..sort();
            for (final n in numbers) {
              final airsAtUtc = seasonMap[n];
              if (airsAtUtc == null) continue;
              final availableAt =
                  airsAtUtc.add(Duration(hours: lagHours)).toLocal();
              if (_inRecentCountWindow(availableAt, now)) showRecentCount++;
              if (showRecentCount >= kUpNextRecentCountMaxPerShow) break;
            }
          } else if (_inRecentCountWindow(lastAirDate, now)) {
            // Date-only fallback: no season map resolved, so all we know
            // is the last-aired episode's calendar date.
            showRecentCount = 1;
          }
        }
      }
    } catch (_) {
      showRecentCount = 0;
    }

    try {
      final candidates = upNextCandidates(show);
      if (candidates.isEmpty) return (null, showRecentCount);

      UpNextEpisode? best;
      for (final episode in candidates) {
        DateTime? airsAtUtc;
        try {
          final traktShowId = await resolveTraktShowId(tmdbId);
          if (traktShowId != null) {
            final season = (episode['season_number'] as num?)?.toInt() ?? 0;
            final number = (episode['episode_number'] as num?)?.toInt() ?? 0;
            final seasonMap = await resolveSeasonMap(traktShowId, season);
            airsAtUtc = seasonMap?[number];
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
      return (best, showRecentCount);
    } catch (_) {
      // A single show's candidate-building failing shouldn't sink the
      // row — skip it and let other shows surface.
      return (null, showRecentCount);
    }
  }).toList();

  final results = await Future.wait(fetches);
  if (traktIdCacheDirty) {
    await saveTraktIdCache(prefs, traktIdCache);
  }
  await seasonAirCache.save();

  final fresh = results.map((r) => r.$1).whereType<UpNextEpisode>().toList()
    ..sort((a, b) => a.availableAt.compareTo(b.availableAt));
  final capped = fresh.take(kUpNextMaxTiles).toList();
  final recentCount =
      results.fold<int>(0, (sum, r) => sum + r.$2);
  final data = UpNextData(episodes: capped, recentCount: recentCount);
  await _UpNextDiskCache.save(prefs, data);
  yield data;
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
    next: upcoming.episodes.isEmpty ? null : upcoming.episodes.first,
  );
});
