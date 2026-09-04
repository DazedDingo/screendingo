import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchnext/utils/trakt_season_air_cache.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  group('TraktSeasonAirCache', () {
    test('put/get roundtrip, including a null-valued episode', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      final now = DateTime(2026, 6, 1, 12);
      cache.put(555, 3, {1: DateTime.utc(2026, 5, 1, 2), 2: null}, now);

      final got = cache.get(555, 3, now);
      expect(got, isNotNull);
      expect(got![1], DateTime.utc(2026, 5, 1, 2));
      expect(got.containsKey(2), isTrue);
      expect(got[2], isNull);
    });

    test('get returns null for an absent key', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      expect(cache.get(1, 1, DateTime.now()), isNull);
    });

    test('TTL expiry — stale beyond kSeasonAirCacheTtl returns null',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      final fetchedAt = DateTime(2026, 1, 1, 0, 0);
      cache.put(1, 1, {1: DateTime.utc(2026, 1, 1)}, fetchedAt);

      // Just inside the TTL.
      final within = fetchedAt.add(kSeasonAirCacheTtl - const Duration(minutes: 1));
      expect(cache.get(1, 1, within), isNotNull);

      // Just outside.
      final stale = fetchedAt.add(kSeasonAirCacheTtl + const Duration(minutes: 1));
      expect(cache.get(1, 1, stale), isNull);
    });

    test('dirty-only save — no write when nothing was put', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      await cache.save();
      expect(prefs.getString(kTraktSeasonAirCacheKey), isNull);
    });

    test('save persists after a put, and a fresh instance can read it back',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      final now = DateTime.now();
      cache.put(10, 2, {1: DateTime.utc(2026, 1, 1)}, now);
      await cache.save();
      expect(prefs.getString(kTraktSeasonAirCacheKey), isNotNull);

      final reloaded = TraktSeasonAirCache(prefs);
      final got = reloaded.get(10, 2, now);
      expect(got, isNotNull);
      expect(got![1], DateTime.utc(2026, 1, 1));
    });

    test('60-day prune on save drops entries older than kSeasonAirCachePruneAge',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      final old = DateTime.now().subtract(const Duration(days: 61));
      final recent = DateTime.now().subtract(const Duration(days: 1));
      cache.put(1, 1, {1: DateTime.utc(2020, 1, 1)}, old);
      cache.put(2, 1, {1: DateTime.utc(2026, 1, 1)}, recent);
      await cache.save();

      final reloaded = TraktSeasonAirCache(prefs);
      // The old entry is gone entirely (not just TTL-stale) — get() with
      // `now` set back to the original fetch time would still return null
      // post-prune, proving it was actually removed from storage rather
      // than merely expired.
      expect(reloaded.get(1, 1, old), isNull);
      expect(reloaded.get(2, 1, recent), isNotNull);
    });

    test('corrupt JSON on disk starts empty instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        kTraktSeasonAirCacheKey: '{not valid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      expect(cache.get(1, 1, DateTime.now()), isNull);
    });

    test('non-map JSON on disk starts empty instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        kTraktSeasonAirCacheKey: '[1,2,3]',
      });
      final prefs = await SharedPreferences.getInstance();
      final cache = TraktSeasonAirCache(prefs);
      expect(cache.get(1, 1, DateTime.now()), isNull);
    });
  });
}
