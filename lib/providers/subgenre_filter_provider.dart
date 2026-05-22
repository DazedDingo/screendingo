import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/keyword_genre_augment.dart';
import 'mode_provider.dart';

/// Per-mode selected sub-genre tags (snake_case keys from
/// [kKeywordToSubgenres]). Parallel axis to the Genre filter: empty set
/// = no constraint; non-empty = AND-intersection (every selected tag
/// must appear in the rec's `subgenres` set). Composes with Genre as
/// AND (both filters narrow the same surviving pool).
///
/// Persistence mirrors `ModeGenreController`: JSON array of tag names
/// under `wn_subgenres_solo` / `wn_subgenres_together`. Same per-mode
/// pattern as media-type, awards, sort, curator. Personal-use app —
/// no migration needed for legacy installs (absent key reads as empty).
class SubgenreFilterController
    extends StateNotifier<Map<ViewMode, Set<String>>> {
  SubgenreFilterController(this._prefs, Map<ViewMode, Set<String>> initial)
      : super(initial);
  final SharedPreferences _prefs;

  static String _keyFor(ViewMode mode) =>
      mode == ViewMode.solo ? 'wn_subgenres_solo' : 'wn_subgenres_together';

  static Set<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = json.decode(raw);
      if (list is! List) return <String>{};
      return list.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Map<ViewMode, Set<String>> readAll(SharedPreferences prefs) => {
        ViewMode.solo: _decode(prefs.getString(_keyFor(ViewMode.solo))),
        ViewMode.together: _decode(prefs.getString(_keyFor(ViewMode.together))),
      };

  Future<void> set(ViewMode mode, Set<String> tags) async {
    state = {...state, mode: {...tags}};
    final key = _keyFor(mode);
    if (tags.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, json.encode(tags.toList()..sort()));
    }
  }

  Future<void> toggle(ViewMode mode, String tag) async {
    final current = {...state[mode] ?? const <String>{}};
    if (!current.add(tag)) current.remove(tag);
    await set(mode, current);
  }

  Future<void> clear(ViewMode mode) => set(mode, const <String>{});
}

/// Exposed so tests can `overrideWithValue(AsyncValue.data(prefs))` and
/// skip the real SharedPreferences.getInstance() async boot.
final subgenrePrefsProvider =
    FutureProvider<SharedPreferences>((_) => SharedPreferences.getInstance());

final modeSubgenreProvider = StateNotifierProvider<SubgenreFilterController,
    Map<ViewMode, Set<String>>>((ref) {
  final prefs = ref.watch(subgenrePrefsProvider).value;
  if (prefs == null) {
    return SubgenreFilterController(
      _UnsetPrefs(),
      const {ViewMode.solo: <String>{}, ViewMode.together: <String>{}},
    );
  }
  return SubgenreFilterController(
    prefs,
    SubgenreFilterController.readAll(prefs),
  );
});

/// Active-mode slice of [modeSubgenreProvider]. Empty = no filter.
final selectedSubGenresProvider = Provider<Set<String>>((ref) {
  final mode = ref.watch(viewModeProvider);
  final map = ref.watch(modeSubgenreProvider);
  return map[mode] ?? const <String>{};
});

class _UnsetPrefs implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => true;
  @override
  Future<bool> remove(String key) async => true;
  @override
  String? getString(String key) => null;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
