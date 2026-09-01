import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchnext/models/watch_entry.dart';
import 'package:watchnext/models/watchlist_item.dart';
import 'package:watchnext/providers/tmdb_provider.dart';
import 'package:watchnext/providers/trakt_provider.dart';
import 'package:watchnext/providers/up_next_lag_provider.dart';
import 'package:watchnext/providers/upnext_history_provider.dart';
import 'package:watchnext/providers/watch_entries_provider.dart';
import 'package:watchnext/providers/watchlist_provider.dart';
import 'package:watchnext/services/tmdb_service.dart';
import 'package:watchnext/services/trakt_service.dart';

// Test-only fixed-value controller — mirrors `_FixedLagController` in
// upnext_provider_test.dart so the history provider's lag can be pinned
// without a real SharedPreferences round trip.
class _FixedLagController extends StateNotifier<int>
    implements UpNextLagController {
  _FixedLagController(super.value);

  @override
  Future<void> set(int hours) async {
    state = hours;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

http.Response _json(Object payload) => http.Response(
      json.encode(payload),
      200,
      headers: const {'content-type': 'application/json'},
    );

String _dateStr(int daysFromToday) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = today.add(Duration(days: daysFromToday));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

WatchEntry _watchingTv(int tmdbId) {
  return WatchEntry(
    id: 'tv:$tmdbId',
    mediaType: 'tv',
    tmdbId: tmdbId,
    title: 'Show $tmdbId',
    inProgressStatus: 'watching',
  );
}

ProviderContainer _container({
  required http.Client client,
  required List<WatchEntry> entries,
  List<WatchlistItem> watchlist = const [],
  // Default: every Trakt call 404s, so tests that don't care about the
  // real-air-time path keep the pre-Trakt date-only fallback behaviour.
  http.Client? traktClient,
  int lagHours = kUpNextLagHoursDefault,
}) {
  final container = ProviderContainer(overrides: [
    tmdbServiceProvider.overrideWithValue(TmdbService(client: client)),
    traktServiceProvider.overrideWithValue(TraktService(
      client: traktClient ??
          MockClient((_) async => http.Response('not found', 404)),
      db: FakeFirebaseFirestore(),
    )),
    upNextLagHoursProvider.overrideWith((_) => _FixedLagController(lagHours)),
    watchEntriesProvider.overrideWith((_) => Stream.value(entries)),
    watchlistProvider.overrideWith((_) => Stream.value(watchlist)),
    visibleWatchlistProvider.overrideWithValue(watchlist),
  ]);
  // autoDispose — without an active listener it can get disposed mid-load
  // and the future read throws "disposed during loading state".
  container.listen<AsyncValue<List<UpNextHistoryEntry>>>(
    upNextHistoryProvider,
    (_, _) {},
  );
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  group('upNextHistoryProvider', () {
    test('returns empty when no shows are eligible', () async {
      final client = MockClient((_) async => _json({}));
      final container = _container(client: client, entries: const []);
      addTearDown(container.dispose);
      final out = await container.read(upNextHistoryProvider.future);
      expect(out, isEmpty);
    });

    test(
        'Trakt-resolved times: entries for in-window episodes only, '
        'sorted desc, hasAirTime true, availableAt = first_aired+lag',
        () async {
      final ep5AirsAt =
          DateTime.now().toUtc().subtract(const Duration(days: 2));
      final ep4AirsAt =
          DateTime.now().toUtc().subtract(const Duration(days: 3));
      final ep1AirsAt =
          DateTime.now().toUtc().subtract(const Duration(days: 40));

      final tmdbClient = MockClient((req) async {
        if (req.url.path.endsWith('/tv/100')) {
          return _json({
            'id': 100,
            'name': 'Test Show',
            'poster_path': '/p.jpg',
            'last_episode_to_air': {
              'season_number': 1,
              'episode_number': 5,
              'air_date': _dateStr(-2),
            },
          });
        }
        if (req.url.path.endsWith('/tv/100/season/1')) {
          return _json({
            'episodes': [
              {
                'episode_number': 1,
                'name': 'Old One',
                'air_date': _dateStr(-40),
              },
              {
                'episode_number': 4,
                'name': 'Recent Four',
                'air_date': _dateStr(-3),
              },
              {
                'episode_number': 5,
                'name': 'Recent Five',
                'air_date': _dateStr(-2),
              },
            ],
          });
        }
        return http.Response('not mocked: ${req.url}', 404);
      });
      final traktClient = MockClient((req) async {
        if (req.url.path.contains('/search/tmdb/100')) {
          return _json([
            {
              'type': 'show',
              'show': {
                'ids': {'trakt': 555}
              },
            },
          ]);
        }
        if (req.url.path.contains('/shows/555/seasons/1/episodes/1')) {
          return _json({'first_aired': ep1AirsAt.toIso8601String()});
        }
        if (req.url.path.contains('/shows/555/seasons/1/episodes/4')) {
          return _json({'first_aired': ep4AirsAt.toIso8601String()});
        }
        if (req.url.path.contains('/shows/555/seasons/1/episodes/5')) {
          return _json({'first_aired': ep5AirsAt.toIso8601String()});
        }
        return http.Response('not mocked trakt: ${req.url}', 404);
      });

      final container = _container(
        client: tmdbClient,
        entries: [_watchingTv(100)],
        traktClient: traktClient,
        lagHours: 0,
      );
      addTearDown(container.dispose);
      final out = await container.read(upNextHistoryProvider.future);

      expect(out, hasLength(2),
          reason: '40-days-old episode 1 is outside the 14-day window');
      expect(out[0].number, 5);
      expect(out[1].number, 4);
      expect(out[0].hasAirTime, isTrue);
      expect(out[0].availableAt.isAtSameMomentAs(ep5AirsAt), isTrue);
      expect(out[1].availableAt.isAtSameMomentAs(ep4AirsAt), isTrue);
    });

    test('Trakt 404 falls back to date-only fallback entries', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/tv/220')) {
          return _json({
            'id': 220,
            'name': 'No Trakt Match',
            'last_episode_to_air': {
              'season_number': 1,
              'episode_number': 2,
              'air_date': _dateStr(-2),
            },
          });
        }
        if (req.url.path.endsWith('/tv/220/season/1')) {
          return _json({
            'episodes': [
              {'episode_number': 1, 'air_date': _dateStr(-3)},
              {'episode_number': 2, 'air_date': _dateStr(-2)},
            ],
          });
        }
        return http.Response('not mocked: ${req.url}', 404);
      });
      final container =
          _container(client: client, entries: [_watchingTv(220)]);
      addTearDown(container.dispose);
      final out = await container.read(upNextHistoryProvider.future);

      expect(out, hasLength(2));
      expect(out.every((e) => !e.hasAirTime), isTrue);
      final today = DateTime.now();
      final expectedAirDate2 = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 2));
      expect(out.first.availableAt, expectedAirDate2);
    });

    test(
        'last episode older than 14 days skips the season fetch entirely '
        'and yields no entries', () async {
      var seasonCalls = 0;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/tv/300')) {
          return _json({
            'id': 300,
            'name': 'Stale Show',
            'last_episode_to_air': {
              'season_number': 1,
              'episode_number': 3,
              'air_date': _dateStr(-20),
            },
          });
        }
        if (req.url.path.contains('/season/')) {
          seasonCalls++;
          return _json({'episodes': []});
        }
        return http.Response('not mocked: ${req.url}', 404);
      });
      final container =
          _container(client: client, entries: [_watchingTv(300)]);
      addTearDown(container.dispose);
      final out = await container.read(upNextHistoryProvider.future);

      expect(out, isEmpty);
      expect(seasonCalls, 0,
          reason: 'a last episode older than the lookback window should '
              'never trigger a season fetch');
    });

    test('excludes future episodes present in the season payload', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/tv/400')) {
          return _json({
            'id': 400,
            'name': 'Mixed Show',
            'last_episode_to_air': {
              'season_number': 1,
              'episode_number': 5,
              'air_date': _dateStr(-2),
            },
          });
        }
        if (req.url.path.endsWith('/tv/400/season/1')) {
          return _json({
            'episodes': [
              // Anomalous future-dated row inside the <= last.number
              // range — the window filter must still drop it.
              {'episode_number': 3, 'air_date': _dateStr(5)},
              {'episode_number': 5, 'air_date': _dateStr(-2)},
            ],
          });
        }
        return http.Response('not mocked: ${req.url}', 404);
      });
      final container =
          _container(client: client, entries: [_watchingTv(400)]);
      addTearDown(container.dispose);
      final out = await container.read(upNextHistoryProvider.future);

      expect(out.map((e) => e.number).toList(), [5]);
    });

    test("one show's TMDB 500 doesn't sink another show's entries",
        () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/tv/500')) {
          return http.Response('boom', 500);
        }
        if (req.url.path.endsWith('/tv/600')) {
          return _json({
            'id': 600,
            'name': 'Reachable Show',
            'last_episode_to_air': {
              'season_number': 1,
              'episode_number': 1,
              'air_date': _dateStr(-2),
            },
          });
        }
        if (req.url.path.endsWith('/tv/600/season/1')) {
          return _json({
            'episodes': [
              {'episode_number': 1, 'air_date': _dateStr(-2)},
            ],
          });
        }
        return http.Response('not mocked: ${req.url}', 404);
      });
      final container = _container(
        client: client,
        entries: [_watchingTv(500), _watchingTv(600)],
      );
      addTearDown(container.dispose);
      final out = await container.read(upNextHistoryProvider.future);

      expect(out.map((e) => e.tmdbId).toList(), [600]);
    });
  });

  group('historyDayLabel', () {
    test('same calendar day as today → "Today"', () {
      expect(
        historyDayLabel(DateTime(2026, 8, 26), DateTime(2026, 8, 26, 23, 0)),
        'Today',
      );
    });

    test('one calendar day back → "Yesterday"', () {
      expect(
        historyDayLabel(DateTime(2026, 8, 25), DateTime(2026, 8, 26)),
        'Yesterday',
      );
    });

    test('older date → weekday + day + short month, no year', () {
      // 2026-08-23 is a Sunday (verified via `date -d`).
      expect(
        historyDayLabel(DateTime(2026, 8, 23), DateTime(2026, 8, 26)),
        'Sun 23 Aug',
      );
    });

    test('older date across a month boundary formats the earlier month',
        () {
      // 2025-08-30 is a Saturday; today is 2025-09-02.
      expect(
        historyDayLabel(DateTime(2025, 8, 30), DateTime(2025, 9, 2)),
        'Sat 30 Aug',
      );
    });

    test('time-of-day on either argument does not affect the result', () {
      expect(
        historyDayLabel(
            DateTime(2026, 8, 26, 3, 15), DateTime(2026, 8, 26, 22, 0)),
        'Today',
      );
    });
  });

  group('groupHistoryByDay', () {
    UpNextHistoryEntry entry(int tmdbId, DateTime availableAt, {int n = 1}) {
      return UpNextHistoryEntry(
        tmdbId: tmdbId,
        showTitle: 'Show $tmdbId',
        season: 1,
        number: n,
        availableAt: availableAt,
        hasAirTime: false,
      );
    }

    test('groups by local calendar day, days descending', () {
      final grouped = groupHistoryByDay([
        entry(1, DateTime(2026, 8, 24, 10, 0)),
        entry(2, DateTime(2026, 8, 26, 9, 0)),
        entry(3, DateTime(2026, 8, 25, 20, 0)),
      ]);
      expect(grouped.map((e) => e.key).toList(), [
        DateTime(2026, 8, 26),
        DateTime(2026, 8, 25),
        DateTime(2026, 8, 24),
      ]);
    });

    test('entries within a day are sorted descending by availableAt', () {
      final grouped = groupHistoryByDay([
        entry(1, DateTime(2026, 8, 26, 8, 0), n: 1),
        entry(1, DateTime(2026, 8, 26, 20, 0), n: 2),
        entry(1, DateTime(2026, 8, 26, 14, 0), n: 3),
      ]);
      expect(grouped, hasLength(1));
      expect(grouped.first.value.map((e) => e.number).toList(), [2, 3, 1]);
    });

    test('multiple entries on the same day group together', () {
      final grouped = groupHistoryByDay([
        entry(1, DateTime(2026, 8, 26, 8, 0)),
        entry(2, DateTime(2026, 8, 26, 20, 0)),
      ]);
      expect(grouped, hasLength(1));
      expect(grouped.first.value, hasLength(2));
    });

    test('empty input returns empty groups', () {
      expect(groupHistoryByDay(const []), isEmpty);
    });
  });
}
