import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// How long a cached season's air-time map stays valid before a fresh
/// Trakt fetch is warranted. 6h balances "steady-state Home open costs
/// zero Trakt calls" against staleness — a show's just-scheduled episode
/// occasionally has its `first_aired` corrected on Trakt's side within
/// hours of the original fetch.
const Duration kSeasonAirCacheTtl = Duration(hours: 6);

/// SharedPreferences key for the persistent season air-time cache.
const String kTraktSeasonAirCacheKey = 'wn_trakt_season_air';

/// How long a stale entry is kept on disk before [TraktSeasonAirCache.save]
/// prunes it. Generous window so a show the household paused on for months
/// doesn't force a re-fetch the moment they resume, while still bounding
/// unbounded growth from shows that were only briefly tracked.
const Duration kSeasonAirCachePruneAge = Duration(days: 60);

class _SeasonAirEntry {
  final DateTime fetchedAt;
  final Map<int, DateTime?> episodes;
  _SeasonAirEntry({required this.fetchedAt, required this.episodes});
}

/// Persistent, TTL'd cache of Trakt season air-time maps
/// (`TraktService.fetchSeasonFirstAired`), keyed by `"<traktId>:<season>"`.
/// One Trakt call per show-season instead of one per episode — see
/// CLAUDE.md gotchas 52/53. `upNextProvider`, `upNextHistoryProvider`, and
/// the title-detail episode-date provider all share this single on-disk
/// cache, so a season resolved by one surface is free for the others for
/// the rest of the TTL window.
///
/// Stored JSON shape: `{"traktId:season": {"at": fetchedAt ISO string,
/// "eps": {episode number as string: ISO string or null, ...}}}`.
class TraktSeasonAirCache {
  final SharedPreferences _prefs;
  final Map<String, _SeasonAirEntry> _entries;
  bool _dirty = false;

  TraktSeasonAirCache(this._prefs) : _entries = _load(_prefs);

  static String _key(int traktId, int season) => '$traktId:$season';

  static Map<String, _SeasonAirEntry> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kTraktSeasonAirCacheKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, _SeasonAirEntry>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        final atRaw = value['at'] as String?;
        final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
        final epsRaw = value['eps'];
        if (at == null || epsRaw is! Map) return;
        final eps = <int, DateTime?>{};
        epsRaw.forEach((k, v) {
          final number = int.tryParse(k.toString());
          if (number == null) return;
          eps[number] = v is String ? DateTime.tryParse(v) : null;
        });
        out[key.toString()] = _SeasonAirEntry(fetchedAt: at, episodes: eps);
      });
      return out;
    } catch (e) {
      developer.log('Trakt season air cache corrupt, dropping: $e',
          name: 'upnext');
      return {};
    }
  }

  /// Returns the cached episode-number → air-time (UTC) map for
  /// (traktId, season), or null when absent or stale
  /// (`now - fetchedAt > kSeasonAirCacheTtl`).
  Map<int, DateTime?>? get(int traktId, int season, DateTime now) {
    final entry = _entries[_key(traktId, season)];
    if (entry == null) return null;
    if (now.difference(entry.fetchedAt) > kSeasonAirCacheTtl) return null;
    return entry.episodes;
  }

  /// Stores a freshly-fetched season air-time map, marking the cache
  /// dirty so the next [save] persists it.
  void put(int traktId, int season, Map<int, DateTime?> eps, DateTime now) {
    _entries[_key(traktId, season)] =
        _SeasonAirEntry(fetchedAt: now, episodes: Map.of(eps));
    _dirty = true;
  }

  /// Persists the cache to disk when dirty — no-op otherwise. Pruning
  /// entries whose `fetchedAt` is older than [kSeasonAirCachePruneAge]
  /// happens on every save (not just the ones that grow the cache) so a
  /// long-running app slowly sheds seasons nobody's tracked in months.
  Future<void> save() async {
    if (!_dirty) return;
    final cutoff = DateTime.now().subtract(kSeasonAirCachePruneAge);
    _entries.removeWhere((_, entry) => entry.fetchedAt.isBefore(cutoff));
    final encoded = jsonEncode(_entries.map((key, entry) => MapEntry(key, {
          'at': entry.fetchedAt.toIso8601String(),
          'eps': entry.episodes
              .map((k, v) => MapEntry(k.toString(), v?.toIso8601String())),
        })));
    await _prefs.setString(kTraktSeasonAirCacheKey, encoded);
    _dirty = false;
  }
}
