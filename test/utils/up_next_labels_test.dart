import 'package:flutter_test/flutter_test.dart';
import 'package:watchnext/providers/upnext_provider.dart';
import 'package:watchnext/utils/up_next_labels.dart';

UpNextEpisode _ep({
  required int daysUntilAir,
  DateTime? availableAt,
  DateTime? airsAtUtc,
}) {
  final airDate = DateTime(2026, 4, 26);
  return UpNextEpisode(
    tmdbId: 1,
    showTitle: 'Show',
    season: 1,
    number: 1,
    airDate: airDate,
    availableAt: availableAt ?? airDate,
    airsAtUtc: airsAtUtc,
    daysUntilAir: daysUntilAir,
  );
}

void main() {
  group('upNextRelativeLabel', () {
    test('d == 0, no air time → "Out today"', () {
      final e = _ep(daysUntilAir: 0);
      expect(upNextRelativeLabel(e), 'Out today');
    });

    test('d == 0, has air time, now before availableAt → "Today ~HH:mm"', () {
      final availableAt = DateTime(2026, 4, 26, 20, 0);
      final e = _ep(
        daysUntilAir: 0,
        availableAt: availableAt,
        airsAtUtc: DateTime.utc(2026, 4, 26, 14),
      );
      final now = DateTime(2026, 4, 26, 19, 0);
      expect(upNextRelativeLabel(e, now: now), 'Today ~20:00');
    });

    test('d == 0, has air time, now at/after availableAt → "Out now"', () {
      final availableAt = DateTime(2026, 4, 26, 20, 0);
      final e = _ep(
        daysUntilAir: 0,
        availableAt: availableAt,
        airsAtUtc: DateTime.utc(2026, 4, 26, 14),
      );
      final now = DateTime(2026, 4, 26, 20, 0);
      expect(upNextRelativeLabel(e, now: now), 'Out now');
      final later = DateTime(2026, 4, 26, 22, 15);
      expect(upNextRelativeLabel(e, now: later), 'Out now');
    });

    test('d == 1, no air time → "Tomorrow"', () {
      final e = _ep(daysUntilAir: 1);
      expect(upNextRelativeLabel(e), 'Tomorrow');
    });

    test('d == 1, has air time → "Tomorrow ~HH:mm"', () {
      final availableAt = DateTime(2026, 4, 27, 8, 5);
      final e = _ep(
        daysUntilAir: 1,
        availableAt: availableAt,
        airsAtUtc: DateTime.utc(2026, 4, 27, 2),
      );
      expect(upNextRelativeLabel(e), 'Tomorrow ~08:05');
    });

    test('d == -1 → "Aired yesterday"', () {
      final e = _ep(daysUntilAir: -1);
      expect(upNextRelativeLabel(e), 'Aired yesterday');
    });

    test('d < -1 → "Just aired"', () {
      expect(upNextRelativeLabel(_ep(daysUntilAir: -2)), 'Just aired');
      expect(upNextRelativeLabel(_ep(daysUntilAir: -5)), 'Just aired');
    });

    test('d > 1 → "In {d}d"', () {
      expect(upNextRelativeLabel(_ep(daysUntilAir: 3)), 'In 3d');
      expect(upNextRelativeLabel(_ep(daysUntilAir: 7)), 'In 7d');
    });
  });

  group('upNextRelativeLabelCompact', () {
    test('d == 0, no air time → "today"', () {
      final e = _ep(daysUntilAir: 0);
      expect(upNextRelativeLabelCompact(e), 'today');
    });

    test('d == 0, has air time, now before availableAt → "today ~HH:mm"', () {
      final availableAt = DateTime(2026, 4, 26, 20, 0);
      final e = _ep(
        daysUntilAir: 0,
        availableAt: availableAt,
        airsAtUtc: DateTime.utc(2026, 4, 26, 14),
      );
      final now = DateTime(2026, 4, 26, 19, 0);
      expect(upNextRelativeLabelCompact(e, now: now), 'today ~20:00');
    });

    test('d == 0, has air time, now at/after availableAt → "out now"', () {
      final availableAt = DateTime(2026, 4, 26, 20, 0);
      final e = _ep(
        daysUntilAir: 0,
        availableAt: availableAt,
        airsAtUtc: DateTime.utc(2026, 4, 26, 14),
      );
      final now = DateTime(2026, 4, 26, 20, 0);
      expect(upNextRelativeLabelCompact(e, now: now), 'out now');
    });

    test('d == 1, no air time → "tomorrow"', () {
      final e = _ep(daysUntilAir: 1);
      expect(upNextRelativeLabelCompact(e), 'tomorrow');
    });

    test('d == 1, has air time → "tomorrow ~HH:mm"', () {
      final availableAt = DateTime(2026, 4, 27, 8, 5);
      final e = _ep(
        daysUntilAir: 1,
        availableAt: availableAt,
        airsAtUtc: DateTime.utc(2026, 4, 27, 2),
      );
      expect(upNextRelativeLabelCompact(e), 'tomorrow ~08:05');
    });

    test('d < 0 (yesterday and further past) → "just aired"', () {
      expect(upNextRelativeLabelCompact(_ep(daysUntilAir: -1)), 'just aired');
      expect(upNextRelativeLabelCompact(_ep(daysUntilAir: -4)), 'just aired');
    });

    test('d > 1 → "in {d}d"', () {
      expect(upNextRelativeLabelCompact(_ep(daysUntilAir: 3)), 'in 3d');
      expect(upNextRelativeLabelCompact(_ep(daysUntilAir: 7)), 'in 7d');
    });
  });
}
