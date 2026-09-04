import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchnext/providers/season_air_map_provider.dart';
import 'package:watchnext/providers/trakt_provider.dart';
import 'package:watchnext/services/trakt_service.dart';

http.Response _json(Object payload) => http.Response(
      json.encode(payload),
      200,
      headers: const {'content-type': 'application/json'},
    );

ProviderContainer _container(http.Client traktClient) {
  return ProviderContainer(overrides: [
    traktServiceProvider.overrideWithValue(TraktService(
      client: traktClient,
      db: FakeFirebaseFirestore(),
    )),
  ]);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  group('seasonAirMapProvider', () {
    test('resolves traktId then the season air map', () async {
      final traktClient = MockClient((req) async {
        if (req.url.path.contains('/search/tmdb/100')) {
          return _json([
            {
              'type': 'show',
              'show': {'ids': {'trakt': 555}},
            },
          ]);
        }
        if (req.url.path.contains('/shows/555/seasons/3')) {
          return _json([
            {'number': 1, 'first_aired': '2026-05-01T02:00:00.000Z'},
            {'number': 2, 'first_aired': null},
          ]);
        }
        return http.Response('not mocked: ${req.url}', 404);
      });
      final container = _container(traktClient);
      addTearDown(container.dispose);

      final result =
          await container.read(seasonAirMapProvider((100, 3)).future);
      expect(result, isNotNull);
      expect(result![1], DateTime.utc(2026, 5, 1, 2));
      expect(result.containsKey(2), isTrue);
      expect(result[2], isNull);
    });

    test('falls back to null when the show has no Trakt match (404)',
        () async {
      final traktClient =
          MockClient((_) async => http.Response('nope', 404));
      final container = _container(traktClient);
      addTearDown(container.dispose);

      final result =
          await container.read(seasonAirMapProvider((999, 1)).future);
      expect(result, isNull);
    });

    test('falls back to null when the season fetch fails after a resolved '
        'traktId', () async {
      final traktClient = MockClient((req) async {
        if (req.url.path.contains('/search/tmdb/200')) {
          return _json([
            {
              'type': 'show',
              'show': {'ids': {'trakt': 700}},
            },
          ]);
        }
        // Season endpoint 404s.
        return http.Response('nope', 404);
      });
      final container = _container(traktClient);
      addTearDown(container.dispose);

      final result =
          await container.read(seasonAirMapProvider((200, 1)).future);
      expect(result, isNull);
    });

    test('reuses the on-disk season cache on a second read (no repeat '
        'Trakt calls)', () async {
      var searchCalls = 0;
      var seasonCalls = 0;
      final traktClient = MockClient((req) async {
        if (req.url.path.contains('/search/tmdb/300')) {
          searchCalls++;
          return _json([
            {
              'type': 'show',
              'show': {'ids': {'trakt': 800}},
            },
          ]);
        }
        if (req.url.path.contains('/shows/800/seasons/1')) {
          seasonCalls++;
          return _json([
            {'number': 1, 'first_aired': '2026-01-01T00:00:00.000Z'},
          ]);
        }
        return http.Response('not mocked: ${req.url}', 404);
      });

      final container1 = _container(traktClient);
      await container1.read(seasonAirMapProvider((300, 1)).future);
      container1.dispose();
      expect(searchCalls, 1);
      expect(seasonCalls, 1);

      final container2 = _container(traktClient);
      addTearDown(container2.dispose);
      await container2.read(seasonAirMapProvider((300, 1)).future);

      expect(searchCalls, 1,
          reason: 'second read should reuse the cached tmdb->trakt id');
      expect(seasonCalls, 1,
          reason: 'second read should reuse the warm on-disk season cache');
    });
  });
}
