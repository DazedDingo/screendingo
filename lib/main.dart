import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'demo/demo_mode.dart';
import 'demo/demo_overrides.dart';
import 'providers/ask_ai_placement_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/up_next_style_provider.dart';
import 'services/home_widget_service.dart';

/// Optional auto-sign-in token, baked into the build via
/// `--dart-define=AUTO_SIGN_IN_TOKEN=...`. Used by the screenshots-real
/// CI workflow to skip Google Sign-In UI on a freshly-booted emulator:
/// firebase-admin mints a short-lived custom token server-side, the
/// workflow bakes it into the debug APK, and `main()` exchanges it for
/// a real user session before the router decides where to land. Empty
/// in normal builds → no auto-sign-in → router falls through to /login
/// exactly as before.
const String _kAutoSignInToken =
    String.fromEnvironment('AUTO_SIGN_IN_TOKEN', defaultValue: '');

/// Background FCM handler. Runs in its own isolate when a data message
/// arrives while the app is killed/backgrounded. MUST be a top-level
/// (or static) function — registering an instance method as a background
/// handler is silently dropped by the platform.
///
/// Only handles `type=refresh_widget` from the `refreshUpNextWidget`
/// Cloud Function. Other payloads (reveal_ready, next_episode_today)
/// arrive with a `notification` block and are shown by the OS without
/// needing our hook — the foreground tap handler in
/// `notification_service.dart` is what routes those to a screen.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The background isolate has its own Firebase instance and needs init.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  if (data['type'] == 'refresh_widget') {
    try {
      await HomeWidgetService.pushUpNextFromFcmPayload(data);
    } catch (_) {
      // Best-effort — a bg refresh failing must never crash the isolate.
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnostic — confirm kDemoMode value at runtime. debugPrint reliably
  // routes to logcat under the `flutter` tag in debug builds (where
  // developer.log was apparently being dropped by something in the
  // CI screenshots emulator pipeline).
  debugPrint('WN_BOOT kDemoMode=$kDemoMode');
  // Replace the default gray rectangle shown on build failures in release
  // mode — we'd rather see the actual error than a blank screen. Also
  // push the exception + stack into developer.log so adb logcat captures
  // it; relying on Flutter's default FlutterError.onError was unreliable
  // in the DEMO_MODE screenshot runs (multiple errors silently absent
  // from logcat, likely rolled out of the 10240-line buffer before
  // adb logcat -d dumped it).
  ErrorWidget.builder = (details) {
    debugPrint('WN_ERR ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint('WN_ERR_STACK ${details.stack}');
    }
    return Material(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              const Text('Something went wrong rendering this screen',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  };
  // DEMO_MODE: skip Firebase init entirely. With the dummy
  // google-services.json the screenshots workflow uses, Firebase init +
  // App Check + FCM heartbeat-registration all deadlock waiting for
  // Google's auth services to respond — repeated "Long monitor contention"
  // log lines, Flutter engine loads but runApp is never reached, system
  // splash sticks forever. Demo mode doesn't need any of it: router is
  // bypassed (app.dart), data providers are overridden (demo_overrides.dart),
  // ScaffoldWithNavBar's direct FirebaseAuth.instance.currentUser calls
  // are already in try/catch and silently no-op when Firebase is missing.
  if (!kDemoMode) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // App Check — attestation layer that proves a Cloud Function call is
    // coming from the genuine, Play-installed ScreenDingo app (and not a
    // reverse-engineered client, scraper, or scripted attacker). Initialised
    // in monitoring mode currently — the Firebase console accepts tokens
    // but Cloud Functions don't reject calls without them. Once we flip
    // enforcement on the Gemini-spending CFs (concierge,
    // scoreRecommendations, fetchExternalRatings) after Play launch + a
    // day of monitoring logs, this becomes the hard gate that protects
    // the metered third-party quotas from abuse.
    //
    // Debug provider for local + sideload builds so kDebugMode flows
    // continue working without registering debug tokens — Play Integrity
    // attestations only ever succeed on Play-installed apps, so any debug
    // build using the production provider would fail attestation and be
    // rejected once enforcement is on. The `kDebugMode` flag flips this
    // to the debug provider in dev; release builds use Play Integrity.
    //
    // Wrapped in try/catch because App Check initialisation throws on
    // certain test runners + on a device that's lost Play Services. We
    // never want the app to fail to start because of a security-layer
    // hiccup — losing attestation just means CF calls go through without
    // tokens (and get rejected if enforcement is on, which we control
    // server-side).
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (e, st) {
      developer.log('App Check activation failed (non-fatal)',
          name: 'wn.appCheck', error: e, stackTrace: st);
    }

    // Auto-sign-in for the screenshots-real CI workflow. The token is
    // minted by firebase-admin in CI against a long-lived
    // "screenshot test household" uid and baked into the build as a
    // dart-define. We swap it for a real Firebase session here so the
    // app boots straight into Home with the pre-seeded Firestore data,
    // bypassing the Google Sign-In UI that GHA emulators can't drive.
    // Empty token → no auto-sign-in → router behaves exactly as it does
    // for a normal release build.
    if (_kAutoSignInToken.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signInWithCustomToken(_kAutoSignInToken);
        debugPrint('WN_BOOT auto-signed-in via custom token');
      } catch (e, st) {
        debugPrint('WN_BOOT custom token sign-in failed: $e');
        developer.log('Auto sign-in failed (non-fatal)',
            name: 'wn.autoSignIn', error: e, stackTrace: st);
      }
    }

    // Register the background FCM handler BEFORE the app starts listening
    // for messages — Firebase Messaging caches the registration once per
    // process and skipping this means data-only refresh pushes silently
    // no-op when the app isn't already running.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      accentProvider.overrideWith((_) => AccentController(prefs)),
      askAiPlacementProvider
          .overrideWith((_) => AskAiPlacementController(prefs)),
      upNextStyleProvider
          .overrideWith((_) => UpNextStyleController(prefs)),
      onboardingDoneProvider
          .overrideWith((_) => OnboardingController(prefs)),
      // DEMO_MODE: swap every Firestore-coupled provider for curated mock
      // data so the screenshot APK renders a populated household without
      // any auth flow or backend dependency. No-op for production builds.
      if (kDemoMode) ...demoOverrides,
    ],
    child: const ScreenDingoApp(),
  ));
}
