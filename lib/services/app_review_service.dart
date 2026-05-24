import 'dart:developer' as developer;

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bridges the app's "positive moment" signals to Play Store's in-app
/// review API. Only fires the system prompt when ALL of:
///
///   1. App was installed ≥ [kMinAgeDays] ago — first-week churn skews
///      ratings; nudging early adopters before they've had time to like
///      the app produces low scores.
///   2. ≥ [kMinPositiveSignals] positive signals have been recorded
///      (high-star ratings, "loved it" markers, completed Decide
///      sessions). The signal count is the closest in-app proxy for
///      "this user is getting value".
///   3. ≥ [kMinDaysBetweenAsks] days since the last prompt — Play's
///      API silently throttles to a quota anyway, but tracking
///      client-side avoids the wasted "ask but nothing shown" round-trip
///      and lets us decide WHICH positive moment to attach to.
///   4. Running on Play (in_app_review's `isAvailable()` returns true).
///      Sideload APKs silently skip — no-op.
///
/// All counters live in SharedPreferences (`wn_review_*`). Errors from
/// the platform channel are swallowed to log — a failed prompt is never
/// a user-visible problem.
class AppReviewService {
  AppReviewService({InAppReview? plugin, SharedPreferences? prefs})
      : _plugin = plugin ?? InAppReview.instance,
        _prefsOverride = prefs;

  final InAppReview _plugin;
  final SharedPreferences? _prefsOverride;

  // Tunable thresholds. Conservative defaults — better to ask less and
  // get genuine 5-stars than to ask early and get 2-stars.
  static const int kMinAgeDays = 7;
  static const int kMinPositiveSignals = 5;
  static const int kMinDaysBetweenAsks = 60;

  static const _kFirstSeen = 'wn_review_first_seen_ms';
  static const _kSignalCount = 'wn_review_positive_signals';
  static const _kLastAsked = 'wn_review_last_asked_ms';

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  /// Records that the user just hit a positive moment (4-or-5-star
  /// rating, finished a Decide session with a "yes", etc). Bumps the
  /// signal counter and, if the eligibility checks all pass, fires the
  /// review prompt opportunistically.
  Future<void> registerPositiveSignal() async {
    final prefs = await _prefs();
    await _ensureFirstSeen(prefs);
    final next = (prefs.getInt(_kSignalCount) ?? 0) + 1;
    await prefs.setInt(_kSignalCount, next);
    if (next >= kMinPositiveSignals) {
      await _maybeAsk(prefs);
    }
  }

  Future<void> _ensureFirstSeen(SharedPreferences prefs) async {
    if (prefs.getInt(_kFirstSeen) == null) {
      await prefs.setInt(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<bool> _maybeAsk(SharedPreferences prefs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final firstSeen = prefs.getInt(_kFirstSeen) ?? now;
    final ageDays = (now - firstSeen) / (1000 * 60 * 60 * 24);
    if (ageDays < kMinAgeDays) return false;

    final lastAsked = prefs.getInt(_kLastAsked);
    if (lastAsked != null) {
      final daysSinceAsk = (now - lastAsked) / (1000 * 60 * 60 * 24);
      if (daysSinceAsk < kMinDaysBetweenAsks) return false;
    }

    bool available;
    try {
      available = await _plugin.isAvailable();
    } catch (e) {
      // Plugin throws on platforms where the Play services API isn't
      // wired (test runners, broken installs). Treat as unavailable
      // rather than crashing the rating-submit flow.
      developer.log('in_app_review.isAvailable threw',
          name: 'wn.appReview', error: e);
      return false;
    }
    if (!available) return false;

    try {
      await _plugin.requestReview();
      await prefs.setInt(_kLastAsked, now);
      // Reset the signal counter so we don't immediately re-trigger if
      // the user gives another positive signal soon after. They have to
      // earn the next prompt by accumulating another batch of signals
      // PLUS the cooldown elapses.
      await prefs.setInt(_kSignalCount, 0);
      return true;
    } catch (e) {
      developer.log('in_app_review.requestReview threw',
          name: 'wn.appReview', error: e);
      return false;
    }
  }
}
