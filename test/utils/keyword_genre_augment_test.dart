import 'package:flutter_test/flutter_test.dart';
import 'package:watchnext/utils/keyword_genre_augment.dart';

void main() {
  group('augmentGenresWithKeywords', () {
    test('returns existing genres unchanged when no keyword matches', () {
      final out = augmentGenresWithKeywords(
        const ['Drama', 'Thriller'],
        const [999999], // unknown id
      );
      expect(out, ['Drama', 'Thriller']);
    });

    test('unions mapped extras into the genre list', () {
      // 9951 = alien (seeded → Science Fiction)
      final out = augmentGenresWithKeywords(
        const ['Horror'],
        const [9951],
      );
      expect(out, ['Horror', 'Science Fiction']);
    });

    test('dedupes when the keyword implies a genre already present', () {
      final out = augmentGenresWithKeywords(
        const ['Science Fiction', 'Drama'],
        const [9951], // alien → Science Fiction
      );
      expect(out, ['Science Fiction', 'Drama'],
          reason: 'Sci-Fi already present, no duplicate entry');
    });

    test('handles multiple keywords, unions all extras', () {
      final out = augmentGenresWithKeywords(
        const ['Thriller'],
        const [4458, 9951], // post-apocalyptic + alien → both Science Fiction
      );
      expect(out, ['Thriller', 'Science Fiction'],
          reason: 'distinct keyword ids collapsing to same genre is one entry');
    });

    test('preserves existing-genre order; extras land in iteration order', () {
      final out = augmentGenresWithKeywords(
        const ['Horror', 'Drama'],
        const [4565], // dystopia → Science Fiction
      );
      expect(out, ['Horror', 'Drama', 'Science Fiction']);
    });

    test('empty inputs return empty list', () {
      expect(
        augmentGenresWithKeywords(const [], const []),
        isEmpty,
      );
    });

    test('empty-string genres are dropped from the existing list', () {
      final out = augmentGenresWithKeywords(
        const ['Drama', ''],
        const [],
      );
      expect(out, ['Drama']);
    });

    test('mapping is never subtractive — canonical genres always survive', () {
      // Regression guard: augmenter widens only. A Comedy stays a Comedy
      // even if a keyword implies a totally different genre bucket.
      final out = augmentGenresWithKeywords(
        const ['Comedy'],
        const [9951], // alien → +Science Fiction, but Comedy stays
      );
      expect(out, contains('Comedy'));
      expect(out, contains('Science Fiction'));
    });

    test('unknown keyword ids mixed with known ones still work', () {
      final out = augmentGenresWithKeywords(
        const ['Drama'],
        const [999999, 9715], // unknown + superhero → Action
      );
      expect(out, ['Drama', 'Action']);
    });

    test('sci-fi + war crossover keywords widen into War', () {
      // Regression lock for the "Sci-Fi + War returns nothing" bug: titles
      // like Starship Troopers are canonically {Action, Adventure, Sci-Fi}
      // on TMDB, so AND-intersection filters zero out without keyword
      // augmentation.
      for (final kid in const [1826, 14909, 2902]) {
        final out = augmentGenresWithKeywords(
          const ['Action', 'Adventure', 'Science Fiction'],
          [kid],
        );
        expect(out, contains('War'),
            reason: 'keyword $kid should pull in War');
        expect(out, contains('Science Fiction'));
      }
    });

    test('space western widens into both Sci-Fi and Western', () {
      final out = augmentGenresWithKeywords(
        const ['Action'],
        const [11606], // space western
      );
      expect(out, containsAll(const ['Science Fiction', 'Western']));
    });

    test('cosmic horror widens into Horror AND Sci-Fi', () {
      final out = augmentGenresWithKeywords(
        const ['Drama'],
        const [215959], // cosmic horror
      );
      expect(out, containsAll(const ['Horror', 'Science Fiction']));
    });
  });

  group('kKeywordsVersion', () {
    test('is a positive int; bump when adding retroactive entries', () {
      // This test doesn't assert a specific value — it just ensures the
      // version exists and is sane. The semantics (rec docs with an older
      // stored version get re-augmented) are covered in
      // recommendations_service_test.dart.
      expect(kKeywordsVersion, greaterThan(0));
    });

    test('bumped to >=3 when sub-genre map shipped', () {
      // Adding kKeywordToSubgenres alongside kKeywordToExtraGenres widens
      // the augmentation contract, so existing rec docs need to re-fetch
      // keywords to pick up the new sub-genre tags. Locks in the bump.
      expect(kKeywordsVersion, greaterThanOrEqualTo(3));
    });
  });

  group('kKeywordToSubgenres', () {
    test('contains the verified core sub-genre tags from spec', () {
      // Verified against TMDB /search/keyword on 2026-04-28; locks each
      // shipped tag against a known keyword id so a rename / drop is
      // caught by tests instead of being a silent regression.
      // wildlife: nature documentary
      expect(kKeywordToSubgenres[221355], contains('wildlife'));
      // true_crime
      expect(kKeywordToSubgenres[33722], contains('true_crime'));
      // music_doc
      expect(kKeywordToSubgenres[246377], contains('music_doc'));
      // history_doc
      expect(kKeywordToSubgenres[321490], contains('history_doc'));
      // science_tech
      expect(kKeywordToSubgenres[287067], contains('science_tech'));
      // sport_doc
      expect(kKeywordToSubgenres[159290], contains('sport_doc'));
      // slasher
      expect(kKeywordToSubgenres[12339], contains('slasher'));
      // cyberpunk
      expect(kKeywordToSubgenres[12190], contains('cyberpunk'));
      // space_opera
      expect(kKeywordToSubgenres[161176], contains('space_opera'));
      // found_footage
      expect(kKeywordToSubgenres[163053], contains('found_footage'));
      // vampire
      expect(kKeywordToSubgenres[3133], contains('vampire'));
      // zombie
      expect(kKeywordToSubgenres[12377], contains('zombie'));
    });

    test('multiple keyword ids map to the same sub-genre tag', () {
      // wildlife has 6 keyword ids — any one of them tagged on a title
      // should widen its sub-genre set to include 'wildlife'.
      final wildlifeKeywords = kKeywordToSubgenres.entries
          .where((e) => e.value.contains('wildlife'))
          .map((e) => e.key)
          .toList();
      expect(wildlifeKeywords.length, greaterThan(1),
          reason: 'wildlife should have multiple TMDB keyword ids');
    });
  });

  group('augmentSubgenresWithKeywords', () {
    test('returns empty for empty inputs', () {
      expect(augmentSubgenresWithKeywords(const [], const []), isEmpty);
    });

    test('returns current set unchanged when no keyword matches', () {
      final out = augmentSubgenresWithKeywords(
        const {'wildlife'},
        const [999999], // unknown id
      );
      expect(out, {'wildlife'});
    });

    test('unions mapped extras into the sub-genre set', () {
      // 33722 = true crime
      final out = augmentSubgenresWithKeywords(
        const <String>{},
        const [33722],
      );
      expect(out, {'true_crime'});
    });

    test('multi-keyword union dedupes when ids share a tag', () {
      // 9902 (wildlife) and 221355 (nature documentary) both map to
      // 'wildlife' — combined input should still yield one tag.
      final out = augmentSubgenresWithKeywords(
        const <String>{},
        const [9902, 221355],
      );
      expect(out, {'wildlife'});
    });

    test('multi-keyword union spans distinct tags', () {
      final out = augmentSubgenresWithKeywords(
        const <String>{},
        const [12339, 12190], // slasher + cyberpunk
      );
      expect(out, containsAll(const ['slasher', 'cyberpunk']));
    });

    test('missing-keyword no-op preserves existing tags', () {
      final out = augmentSubgenresWithKeywords(
        const {'true_crime', 'wildlife'},
        const [999999, 888888], // both unknown
      );
      expect(out, {'true_crime', 'wildlife'});
    });

    test('dedupes when input keyword maps to a tag already present', () {
      final out = augmentSubgenresWithKeywords(
        const {'slasher'},
        const [12339], // slasher again
      );
      expect(out, {'slasher'});
    });

    test('empty-string entries in current set are dropped', () {
      final out = augmentSubgenresWithKeywords(
        const {'', 'true_crime'},
        const [],
      );
      expect(out, {'true_crime'});
    });

    test('is purely additive — never removes existing tags', () {
      // Regression guard mirroring augmentGenresWithKeywords: a comedy
      // stays a comedy. Same here — pre-existing tags survive any
      // keyword input.
      final out = augmentSubgenresWithKeywords(
        const {'space_opera'},
        const [12339], // slasher
      );
      expect(out, containsAll(const ['space_opera', 'slasher']));
    });
  });

  group('subgenreMatches', () {
    test('empty selection always matches (no filter)', () {
      expect(subgenreMatches(const <String>{}, const <String>{}), isTrue);
      expect(subgenreMatches(const {'wildlife'}, const <String>{}), isTrue);
    });

    test('non-empty selection drops recs with empty subgenres set', () {
      // Strict-on-empty contract: same as Genre filter (gotcha 10).
      // An unclassified rec can't be verified as "tagged with all of
      // these", so it drops under any active sub-genre filter.
      expect(subgenreMatches(const <String>{}, const {'wildlife'}), isFalse);
    });

    test('matches when every selected tag is in the rec set', () {
      expect(
        subgenreMatches(
          const {'wildlife', 'true_crime', 'history_doc'},
          const {'wildlife', 'true_crime'},
        ),
        isTrue,
      );
    });

    test('AND-intersection: missing any selected tag drops the rec', () {
      // The rec only has 'wildlife', the selection wants wildlife AND
      // true_crime — must drop.
      expect(
        subgenreMatches(
          const {'wildlife'},
          const {'wildlife', 'true_crime'},
        ),
        isFalse,
      );
    });

    test('exact-match selection passes', () {
      expect(
        subgenreMatches(
          const {'cyberpunk'},
          const {'cyberpunk'},
        ),
        isTrue,
      );
    });

    test('rec with extra unselected tags still matches', () {
      // Rec has more tags than selected — fine, we're testing
      // "contains all of selected", not "exactly equal".
      expect(
        subgenreMatches(
          const {'wildlife', 'history_doc', 'slasher'},
          const {'wildlife'},
        ),
        isTrue,
      );
    });
  });

  group('subgenreLabel + kAllSubgenres + kSubgenreToKeywordIds', () {
    test('subgenreLabel maps known tags to human-readable labels', () {
      expect(subgenreLabel('wildlife'), 'Animal docs');
      expect(subgenreLabel('true_crime'), 'True crime');
      expect(subgenreLabel('slasher'), 'Slasher');
      expect(subgenreLabel('space_opera'), 'Space opera');
    });

    test('subgenreLabel falls back to title-case for unknown tags', () {
      expect(subgenreLabel('made_up_tag'), 'Made Up Tag');
      expect(subgenreLabel('single'), 'Single');
    });

    test('kAllSubgenres contains every shipped tag, alphabetised by label',
        () {
      final tags = kAllSubgenres;
      expect(tags, contains('wildlife'));
      expect(tags, contains('true_crime'));
      expect(tags, contains('slasher'));
      expect(tags, isNotEmpty);
      // Sorted-by-label invariant.
      for (var i = 0; i + 1 < tags.length; i++) {
        expect(
          subgenreLabel(tags[i]).compareTo(subgenreLabel(tags[i + 1])) <= 0,
          isTrue,
          reason:
              '${subgenreLabel(tags[i])} should sort before ${subgenreLabel(tags[i + 1])}',
        );
      }
    });

    test('kSubgenreToKeywordIds inverts the keyword→tag map', () {
      // The inverse: tag → set of keyword ids that imply it.
      final inv = kSubgenreToKeywordIds;
      // wildlife should pull in at least 6 keyword ids (verified spec).
      expect(inv['wildlife'], isNotNull);
      expect(inv['wildlife']!.length, greaterThanOrEqualTo(2));
      // true_crime maps to a single keyword id.
      expect(inv['true_crime'], {33722});
    });
  });

  // ─── Parent-genre contextual sub-topic contract ─────────────────────────
  //
  // Every shipped sub-topic must declare ≥1 parent genre. Without parent
  // declaration the chip would never be visible in the contextual UI
  // (gotcha 43b — only sub-topics whose parent intersects selected genres
  // render), so an unparented tag is dead weight that bloats the map.
  group('kSubgenreParents', () {
    test('every kAllSubgenres tag has a parent declaration', () {
      for (final tag in kAllSubgenres) {
        expect(kSubgenreParents.containsKey(tag), isTrue,
            reason:
                'tag $tag has no kSubgenreParents entry — would never be visible');
        expect(kSubgenreParents[tag]!, isNotEmpty,
            reason: 'tag $tag has empty parent set');
      }
    });

    test('parent names match canonical movie-genre vocabulary', () {
      // Parents must be names from tmdb_genres.dart's MOVIE map (kGenreSynonyms
      // handles TV→movie equivalence at lookup time). A typo'd parent would
      // silently hide every chip for that tag.
      const movieGenres = {
        'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary',
        'Drama', 'Family', 'Fantasy', 'History', 'Horror', 'Music', 'Mystery',
        'Romance', 'Science Fiction', 'Thriller', 'War', 'Western',
      };
      for (final entry in kSubgenreParents.entries) {
        for (final p in entry.value) {
          expect(movieGenres.contains(p), isTrue,
              reason:
                  '${entry.key} → $p is not a canonical movie-genre name');
        }
      }
    });

    test('Documentary sub-topics are all parented under Documentary', () {
      // Smoke: the v0.10.3 Documentary fill (food/travel/political/etc.)
      // shouldn't have drifted parents.
      const docTags = {
        'wildlife', 'true_crime', 'music_doc', 'history_doc',
        'science_tech', 'sport_doc', 'food_doc', 'travel_doc',
        'political_doc', 'environmental_doc',
      };
      for (final tag in docTags) {
        expect(kSubgenreParents[tag], contains('Documentary'),
            reason: '$tag should declare Documentary as a parent');
      }
    });

    test('Crime now has ≥7 distinct sub-topics (lackluster fix)', () {
      final crimeTags = kSubgenreParents.entries
          .where((e) => e.value.contains('Crime'))
          .map((e) => e.key)
          .toSet();
      expect(crimeTags.length, greaterThanOrEqualTo(7),
          reason:
              'Crime parent should host ≥7 sub-topics after v0.10.3 fill; '
              'shipped: $crimeTags');
    });
  });

  // ─── Genre-boost keywords (Horror sparse-results fix) ──────────────────
  //
  // TMDB has no TV Horror genre id, so picking just Horror used to return
  // ~7 movies and zero TV. kGenreBoostKeywords['Horror'] pipes horror
  // keyword ids into the discover query to pull TV horror INTO the pool,
  // and the kKeywordToExtraGenres stamp brings them past the client-side
  // AND filter.
  group('kGenreBoostKeywords', () {
    test('Horror has a non-trivial keyword boost', () {
      final boost = kGenreBoostKeywords['Horror'];
      expect(boost, isNotNull);
      expect(boost!.length, greaterThanOrEqualTo(8),
          reason: 'Horror needs broad keyword coverage to fill the TV pool');
    });

    test('every Horror boost keyword stamps Horror via kKeywordToExtraGenres',
        () {
      // The boost is useless if pulled-in TV titles don't get the Horror
      // genre stamped — the client-side AND filter would drop them. This
      // test pins the symmetry: every id in the boost set MUST have a
      // kKeywordToExtraGenres entry that includes 'Horror'.
      for (final kid in kGenreBoostKeywords['Horror']!) {
        final extras = kKeywordToExtraGenres[kid];
        expect(extras, isNotNull,
            reason:
                'boost keyword $kid is missing from kKeywordToExtraGenres; '
                'TV titles tagged with it would be pulled in but never '
                'stamped as Horror, so the client AND filter would drop them');
        expect(extras!.contains('Horror'), isTrue,
            reason:
                'boost keyword $kid does not augment to Horror — symmetry '
                'broken');
      }
    });
  });
}
