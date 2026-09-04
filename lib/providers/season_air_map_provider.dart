import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/trakt_season_air_cache.dart';
import 'trakt_provider.dart';
import 'upnext_provider.dart' show loadTraktIdCache, saveTraktIdCache;

/// Resolves a TV show season's real Trakt air-time map (episode number →
/// `first_aired` UTC, or null per-episode when Trakt has none) for the
/// title-detail Episodes section — see `_EpisodeRow` in
/// `title_detail_screen.dart` and CLAUDE.md gotcha 44's date-source fix.
///
/// Keyed by `(showTmdbId, seasonNumber)` so every episode row within the
/// same expanded season tile shares ONE resolution (one Trakt id lookup +
/// one season fetch, both cache-backed) instead of a per-row lookup.
/// autoDispose so navigating away from the detail screen releases it.
///
/// Resolution: tmdbId → traktId via the shared on-disk lookup cache
/// ([loadTraktIdCache]/[saveTraktIdCache], same cache `upNextProvider` and
/// `upNextHistoryProvider` use) → season air map via
/// [TraktSeasonAirCache] (6h TTL) → falling through to a real
/// `TraktService.fetchSeasonFirstAired` call on a cache miss. Returns
/// null when the show's Trakt id can't be resolved or the season fetch
/// fails — callers fall back to TMDB's raw date-only `air_date` in that
/// case, exactly like today's rendering.
final seasonAirMapProvider = FutureProvider.autoDispose
    .family<Map<int, DateTime?>?, (int, int)>((ref, key) async {
  final (tmdbId, season) = key;
  final trakt = ref.watch(traktServiceProvider);
  final prefs = await SharedPreferences.getInstance();

  final traktIdCache = loadTraktIdCache(prefs);
  var traktId = traktIdCache[tmdbId];
  if (traktId == null) {
    traktId = await trakt.lookupShowTraktId(tmdbId);
    if (traktId == null) return null;
    traktIdCache[tmdbId] = traktId;
    await saveTraktIdCache(prefs, traktIdCache);
  }

  final now = DateTime.now();
  final cache = TraktSeasonAirCache(prefs);
  final cachedMap = cache.get(traktId, season, now);
  if (cachedMap != null) return cachedMap;

  final fetched = await trakt.fetchSeasonFirstAired(
    traktShowId: traktId,
    season: season,
  );
  if (fetched != null) {
    cache.put(traktId, season, fetched, now);
    await cache.save();
  }
  return fetched;
});
