import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many hours after real broadcast an episode is typically available
/// to stream (torrents/streaming services lag the network's air time,
/// often by several hours — a household in a different timezone from the
/// airing network feels this doubly). `UpNextEpisode.availableAt` is
/// computed as Trakt's real `first_aired` (UTC) plus this many hours; the
/// user tunes it here to match how quickly their sources typically catch
/// up. Default 6h is a reasonable middle ground when no better signal
/// exists.
const kUpNextLagHoursKey = 'wn_upnext_lag_hours';
const kUpNextLagHoursDefault = 6;
const kUpNextLagChoices = [0, 2, 4, 6, 8, 12, 24];

class UpNextLagController extends StateNotifier<int> {
  final SharedPreferences _prefs;

  UpNextLagController(this._prefs) : super(_readValid(_prefs));

  static int _readValid(SharedPreferences prefs) {
    final stored = prefs.getInt(kUpNextLagHoursKey);
    if (stored == null || !kUpNextLagChoices.contains(stored)) {
      return kUpNextLagHoursDefault;
    }
    return stored;
  }

  Future<void> set(int hours) async {
    state = hours;
    await _prefs.setInt(kUpNextLagHoursKey, hours);
  }
}

final upNextLagHoursProvider = StateNotifierProvider<UpNextLagController, int>(
    (ref) {
  throw UnimplementedError('upNextLagHoursProvider not initialised');
});
