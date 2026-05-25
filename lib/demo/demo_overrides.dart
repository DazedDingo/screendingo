/// Riverpod overrides applied when [kDemoMode] is true (see demo_mode.dart).
///
/// Each Firestore-coupled provider listed in
/// `project_screendingo_session_handoff_2026_05_25.md` gets a hardcoded
/// mock stream/value. Downstream "derived" providers (e.g.
/// `watchedKeysProvider` derives from `watchEntriesProvider`) are left
/// alone — they compute correctly from the overridden sources.
///
/// Filter providers (genre, year, runtime, awards, sort, curated,
/// includeWatched, mode) are also left alone; they start at their
/// defaults and the screenshot suite (Phase 3) can drive them
/// programmatically if a screen needs a specific filter state.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/household_provider.dart';
import '../providers/not_interested_provider.dart';
import '../providers/ratings_provider.dart';
import '../providers/recommendations_provider.dart';
import '../providers/rewatch_provider.dart';
import '../providers/stats_provider.dart' show tasteProfileProvider;
import '../providers/tonights_pick_provider.dart';
import '../providers/upcoming_provider.dart';
import '../providers/upnext_provider.dart';
import '../providers/watch_entries_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/auth_service.dart';
import 'demo_data.dart';
import 'demo_mode.dart';

/// Drop-in replacement for [AuthService] that never touches
/// `FirebaseAuth.instance`. Used as the override for
/// [authServiceProvider] in demo mode so the AuthService constructor
/// can be invoked safely even when Firebase init was skipped.
///
/// The screenshots build hit a Riverpod quirk where the StreamProvider
/// override for `authStateProvider` was silently bypassed at runtime —
/// the original closure (which reads `ref.watch(authServiceProvider)`)
/// ran, constructed a real AuthService, and crashed at
/// `FirebaseAuth.instance`. Overriding the service provider belt-and-
/// braces the auth path regardless of which Riverpod override fires.
class _DemoAuthService implements AuthService {
  @override
  Stream<User?> get authStateChanges => Stream<User?>.value(null);

  @override
  User? get currentUser => null;

  @override
  Future<UserCredential> signInWithGoogle() =>
      throw UnimplementedError('Sign-in disabled in DEMO_MODE');

  @override
  Future<void> signOut() async {}

  @override
  // ignore: invalid_use_of_protected_member
  noSuchMethod(Invocation invocation) => null;
}

/// List of overrides to apply to the ProviderScope when DEMO_MODE is on.
///
/// Wired in `main.dart` like:
///   ProviderScope(
///     overrides: kDemoMode ? demoOverrides : [],
///     child: const ScreenDingoApp(),
///   )
List<Override> get demoOverrides => [
      // Auth + household — synthetic IDs so downstream providers don't
      // gate-out on null. The router (app.dart) has a separate kDemoMode
      // check that bypasses the FirebaseAuth.currentUser direct call.
      //
      // authStateProvider override is critical: its original closure
      // builds an AuthService and calls .authStateChanges, which touches
      // FirebaseAuth.instance and throws [core/no-app] when Firebase
      // hasn't been initialised. Anything that watches authStateProvider
      // (e.g. notInterestedKeysProvider:106 reads .value?.uid) would
      // crash the build. The User class is sealed so we can't fabricate
      // a non-null user; null is fine because every caller that needs
      // a uid should use currentUidProvider (already overridden) and
      // the few that still read authStateProvider.value?.uid just
      // gracefully get null + no-op.
      // authServiceProvider override is the load-bearing one — see
      // _DemoAuthService doc above. authStateProvider's override goes
      // alongside it but Riverpod doesn't always honour it; this
      // makes the auth path safe even if Riverpod skips the
      // StreamProvider override.
      authServiceProvider.overrideWith((_) => _DemoAuthService()),
      authStateProvider
          .overrideWith((_) => Stream<User?>.value(null)),
      currentUidProvider.overrideWith((_) => kDemoUid),
      householdIdProvider.overrideWith((_) async => kDemoHouseholdId),

      // Core Firestore-coupled streams — every provider that hits
      // /households/{hh}/* gets a curated mock.
      recommendationsProvider
          .overrideWith((_) => Stream.value(demoRecommendations)),
      watchEntriesProvider
          .overrideWith((_) => Stream.value(demoWatchEntries)),
      ratingsProvider.overrideWith((_) => Stream.value(demoRatings)),
      watchlistProvider.overrideWith((_) => Stream.value(demoWatchlist)),
      notInterestedProvider
          .overrideWith((_) => Stream.value(demoNotInterested)),
      tonightsPickProvider
          .overrideWith((_) => Stream.value(demoTonightsPick)),
      tasteProfileProvider
          .overrideWith((_) => Stream.value(demoTasteProfile)),

      // TMDB-sourced surfaces — no network in demo mode.
      upcomingForYouProvider
          .overrideWith((_) => Stream.value(demoUpcoming)),
      upNextProvider.overrideWith((_) => Stream.value(demoUpNext)),
      rewatchForYouProvider.overrideWith((_) => demoRewatch),
    ];
