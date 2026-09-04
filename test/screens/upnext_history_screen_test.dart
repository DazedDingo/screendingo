import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchnext/providers/upnext_history_provider.dart';
import 'package:watchnext/screens/upnext_history/upnext_history_screen.dart';

/// "Recently aired" history screen — widget-level coverage over a fixed
/// `upNextHistoryProvider` override. Pure grouping/label logic is covered
/// in `upnext_history_provider_test.dart`; this file proves the screen
/// wires that logic up into day-grouped headers + row content.
void main() {
  UpNextHistoryEntry entry({
    int tmdbId = 1,
    String showTitle = 'Test Show',
    int season = 1,
    int number = 1,
    String? episodeName,
    required DateTime availableAt,
    bool hasAirTime = false,
  }) {
    return UpNextHistoryEntry(
      tmdbId: tmdbId,
      showTitle: showTitle,
      season: season,
      number: number,
      episodeName: episodeName,
      availableAt: availableAt,
      hasAirTime: hasAirTime,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<UpNextHistoryEntry> entries,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upNextHistoryProvider.overrideWith((ref) => Stream.value(entries)),
        ],
        child: const MaterialApp(home: UpNextHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the AppBar title', (tester) async {
    await pumpScreen(tester, entries: const []);
    expect(find.text('Recently aired'), findsOneWidget);
  });

  testWidgets('empty list shows the muted empty-state message',
      (tester) async {
    await pumpScreen(tester, entries: const []);
    expect(
      find.text('Nothing has aired for your shows in the last 14 days.'),
      findsOneWidget,
    );
  });

  testWidgets('groups entries under Today / Yesterday day headers',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1, hours: -4));

    await pumpScreen(tester, entries: [
      entry(tmdbId: 1, showTitle: 'Today Show', availableAt: today),
      entry(tmdbId: 2, showTitle: 'Yesterday Show', availableAt: yesterday),
    ]);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today Show'), findsOneWidget);
    expect(find.text('Yesterday Show'), findsOneWidget);
  });

  testWidgets(
      'row subtitle formats as S##E## · episode name, omitting the name '
      'when absent', (tester) async {
    final now = DateTime.now();
    await pumpScreen(tester, entries: [
      entry(
        tmdbId: 1,
        showTitle: 'Named Episode Show',
        season: 2,
        number: 5,
        episodeName: 'Big Reveal',
        availableAt: now,
      ),
      entry(
        tmdbId: 2,
        showTitle: 'Nameless Episode Show',
        season: 1,
        number: 3,
        availableAt: now,
      ),
    ]);

    expect(find.text('S02E05 · Big Reveal'), findsOneWidget);
    expect(find.text('S01E03'), findsOneWidget);
  });

  testWidgets('shows a ~HH:mm trailing label only when hasAirTime is true',
      (tester) async {
    final now = DateTime.now();
    final withTime =
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    await pumpScreen(tester, entries: [
      entry(
        tmdbId: 1,
        showTitle: 'Timed Show',
        availableAt: withTime,
        hasAirTime: true,
      ),
      entry(
        tmdbId: 2,
        showTitle: 'Dateless Show',
        availableAt: withTime,
        hasAirTime: false,
      ),
    ]);

    final hh = withTime.hour.toString().padLeft(2, '0');
    final mm = withTime.minute.toString().padLeft(2, '0');
    expect(find.text('~$hh:$mm'), findsOneWidget);
  });
}
