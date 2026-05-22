import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchnext/models/recommendation.dart';
import 'package:watchnext/providers/mode_provider.dart';
import 'package:watchnext/providers/subgenre_filter_provider.dart';
import 'package:watchnext/utils/keyword_genre_augment.dart';

void main() {
  group('SubgenreFilterController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
    });

    test('starts with empty sets for both modes', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      expect(c.state[ViewMode.solo], isEmpty);
      expect(c.state[ViewMode.together], isEmpty);
    });

    test('toggle adds then removes the same tag', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.toggle(ViewMode.solo, 'wildlife');
      expect(c.state[ViewMode.solo], {'wildlife'});
      await c.toggle(ViewMode.solo, 'wildlife');
      expect(c.state[ViewMode.solo], isEmpty);
    });

    test('toggle accumulates multiple distinct tags', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.toggle(ViewMode.solo, 'wildlife');
      await c.toggle(ViewMode.solo, 'slasher');
      expect(c.state[ViewMode.solo], {'wildlife', 'slasher'});
    });

    test('set replaces the whole set for a mode', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.set(ViewMode.solo, {'wildlife', 'slasher'});
      await c.set(ViewMode.solo, {'cyberpunk'});
      expect(c.state[ViewMode.solo], {'cyberpunk'});
    });

    test('clear empties the mode and removes the key', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.set(ViewMode.solo, {'wildlife'});
      expect(prefs.containsKey('wn_subgenres_solo'), isTrue);
      await c.clear(ViewMode.solo);
      expect(c.state[ViewMode.solo], isEmpty);
      expect(prefs.containsKey('wn_subgenres_solo'), isFalse);
    });

    test('solo + together are independent', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.set(ViewMode.solo, {'wildlife'});
      expect(c.state[ViewMode.together], isEmpty);
      await c.set(ViewMode.together, {'true_crime'});
      expect(c.state[ViewMode.solo], {'wildlife'});
      expect(c.state[ViewMode.together], {'true_crime'});
    });

    test('persists as sorted JSON list under per-mode keys', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.set(
          ViewMode.solo, {'true_crime', 'wildlife', 'cyberpunk'});
      final raw = prefs.getString('wn_subgenres_solo');
      expect(raw, isNotNull);
      final decoded = json.decode(raw!) as List;
      expect(decoded, ['cyberpunk', 'true_crime', 'wildlife']);
      expect(prefs.containsKey('wn_subgenres_together'), isFalse);
    });

    test('empty set removes the key rather than writing "[]"', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = SubgenreFilterController(
        prefs,
        SubgenreFilterController.readAll(prefs),
      );
      await c.set(ViewMode.solo, {'wildlife'});
      await c.set(ViewMode.solo, const <String>{});
      expect(prefs.containsKey('wn_subgenres_solo'), isFalse);
    });

    test('readAll hydrates both modes independently from stored JSON',
        () async {
      SharedPreferences.setMockInitialValues({
        'wn_subgenres_solo': json.encode(['wildlife', 'slasher']),
        'wn_subgenres_together': json.encode(['true_crime']),
      });
      final prefs = await SharedPreferences.getInstance();
      final map = SubgenreFilterController.readAll(prefs);
      expect(map[ViewMode.solo], {'wildlife', 'slasher'});
      expect(map[ViewMode.together], {'true_crime'});
    });

    test('malformed JSON in prefs decodes to empty set (forward-compat)',
        () async {
      SharedPreferences.setMockInitialValues(const {
        'wn_subgenres_solo': 'this-is-not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final map = SubgenreFilterController.readAll(prefs);
      expect(map[ViewMode.solo], isEmpty);
    });

    test('JSON non-list decodes to empty set (defensive)', () async {
      SharedPreferences.setMockInitialValues(const {
        'wn_subgenres_solo': '{"not":"a list"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final map = SubgenreFilterController.readAll(prefs);
      expect(map[ViewMode.solo], isEmpty);
    });

    test('non-string entries in stored list are dropped', () async {
      SharedPreferences.setMockInitialValues({
        'wn_subgenres_solo': json.encode(['wildlife', 42, null, 'slasher']),
      });
      final prefs = await SharedPreferences.getInstance();
      final map = SubgenreFilterController.readAll(prefs);
      expect(map[ViewMode.solo], {'wildlife', 'slasher'});
    });
  });

  group('Home-pipeline sub-genre filter step (gotcha 10 contract)', () {
    // Mirrors the inline filter step in lib/screens/home/home_screen.dart:
    //   final subgenreFiltered = selectedSubgenres.isEmpty
    //       ? genreFiltered
    //       : genreFiltered
    //           .where((r) => subgenreMatches(r.subgenres, selectedSubgenres))
    //           .toList();
    // These cases lock the user-facing contract via the real Recommendation
    // model so a regression in either subgenreMatches OR the model wiring
    // surfaces in this suite.

    Recommendation rec(String id, Set<String> subs) => Recommendation(
          id: id,
          mediaType: 'movie',
          tmdbId: int.parse(id),
          title: 'Title $id',
          matchScore: 70,
          subgenres: subs,
        );

    List<Recommendation> filter(
            List<Recommendation> recs, Set<String> selected) =>
        recs.where((r) => subgenreMatches(r.subgenres, selected)).toList();

    test('rec with {wildlife} survives a wildlife filter', () {
      final survivors = filter(
        [rec('1', {'wildlife'})],
        {'wildlife'},
      );
      expect(survivors, hasLength(1));
      expect(survivors.first.id, '1');
    });

    test('same rec drops out under a true_crime-only filter', () {
      final survivors = filter(
        [rec('1', {'wildlife'})],
        {'true_crime'},
      );
      expect(survivors, isEmpty);
    });

    test('same rec survives an empty filter (no constraint)', () {
      final survivors = filter(
        [rec('1', {'wildlife'})],
        const <String>{},
      );
      expect(survivors, hasLength(1));
    });

    test('unclassified rec drops under any active filter', () {
      // Strict-on-empty contract — mirrors gotcha 10.
      final survivors = filter(
        [rec('1', const <String>{})],
        {'wildlife'},
      );
      expect(survivors, isEmpty);
    });

    test('AND-intersection: rec must satisfy every selected tag', () {
      final survivors = filter(
        [
          rec('1', {'wildlife'}),
          rec('2', {'wildlife', 'history_doc'}),
          rec('3', {'history_doc'}),
        ],
        {'wildlife', 'history_doc'},
      );
      expect(survivors.map((r) => r.id), ['2']);
    });
  });
}
