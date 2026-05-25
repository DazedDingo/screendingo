// Integration-test screenshot driver for the Play Store launch set.
//
// Compared to the adb-screencap path in `.github/workflows/screenshots-real.yml`
// (which captures Home at progressive time-beats only — limited variety),
// this driver navigates the running app between captures so we get a
// distinct surface per frame: Home + Tonight's Pick rendered, Filters
// panel expanded, Title Detail, Library, and Profile.
//
// **Data + auth:** runs against real Firebase using the same
// `AUTO_SIGN_IN_TOKEN` dart-define + `functions/scripts/screenshots_setup.ts`
// seed as the existing adb-screencap workflow. No DEMO_MODE. The seeded
// household has Tonight's Pick = Better Call Saul (id `demo_household_1`,
// viewer `demo_uid_alex`) plus 8 watch entries, 6 watchlist items, 12
// recommendations.
//
// **Why driver-extended (option A) over writing to app storage (option B):**
// option B would need either a manifest WRITE_EXTERNAL_STORAGE permission
// (rejected on API 33+ scoped storage) or `getExternalStorageDirectory()`
// + an `adb pull` of the package's sandboxed dir, both of which add CI
// fragility for no real win. The driver-extended pattern is the documented
// idiom — the device-side test calls `binding.takeScreenshot(name)`,
// which pushes the bytes into `reportData['screenshots']`, and the
// host-side `test_driver/integration_test.dart` runner pulls the bytes
// back via the driver channel + writes PNGs to `screenshots/it/` on the
// runner. No on-device file storage involved.
//
// **Android surface-conversion ordering** (gotcha from
// `_callback_io.dart` in the integration_test SDK):
// `binding.convertFlutterSurfaceToImage()` has an internal assert that
// it's only ever called ONCE per test — calling it on every
// `takeScreenshot()` invocation throws "Surface already converted to an
// image". Call it once at the start of the test (right after the first
// settle pump) and then take as many screenshots as needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:watchnext/main.dart' as app;

void main() {
  // Bind the test runner. Returned instance is what we drive captures
  // through; `framePolicy = fullyLive` forces real frames to render
  // every tick (the default policy short-circuits frames in test mode,
  // which means `takeScreenshot()` would capture a stale or blank frame
  // — documented in the integration_test README).
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Play Store screenshot capture sweep', (tester) async {
    // Boot the real app entrypoint. Reads `--dart-define=AUTO_SIGN_IN_TOKEN=...`
    // baked into the APK by the GHA workflow, so the splash → auto-sign-in
    // → /home roundtrip happens inside `main()` exactly the same way it
    // does in the adb-screencap pipeline.
    app.main();

    // ── Settle on Home ─────────────────────────────────────────────────
    // The auto-sign-in custom-token exchange typically resolves in ~1-2s
    // on a fresh emulator; Firestore listeners + TMDB poster loads (for
    // Tonight's Pick + Upcoming-for-you carousel) add another ~10-15s on
    // top. Use a generous polling loop instead of a single big sleep so
    // we capture as soon as the household has rendered, not later than
    // we have to.
    //
    // `tester.pumpAndSettle(timeout: ...)` would throw if the app never
    // becomes idle (some screens — Tonight's Pick has an animated
    // wordmark gradient sweep + Up Next marquee that auto-cycles every
    // 4s — are intentionally never idle). Use `tester.pump(duration)`
    // with `findsOneWidget` polling instead, which doesn't depend on
    // an idle frame.
    await _waitForHomeSettled(tester);

    // Convert the Flutter surface to an image — Android only.
    // **Must run exactly once per test session** (asserts in the SDK
    // throw "Surface already converted to an image" on a second call).
    // No-op on other platforms; wrapped in try/catch defensively for
    // any host/runner where the platform channel isn't ready.
    try {
      await binding.convertFlutterSurfaceToImage();
    } catch (e) {
      debugPrint('WN_SS convertFlutterSurfaceToImage failed: $e');
    }

    // ── 1) Home — Tonight's Pick + Recommended-for-you visible ─────────
    await _capture(binding, tester, '01-home');

    // ── 2) Home with Filters panel expanded ────────────────────────────
    // Tapping the "Filter recommendations" header (CLAUDE.md gotcha 15 —
    // `_FiltersPanel` is collapsed by default) expands the panel in-place
    // so the screenshot shows the genre / sub-topic / runtime / year /
    // awards / curator knobs the user can pull.
    //
    // The header is a tappable `InkWell` wrapping a Row with an
    // `Icons.tune` icon + `Text('Filter recommendations')`. The text is
    // the most stable finder — both icon + label are unique on Home.
    final filterHeader = find.text('Filter recommendations');
    if (filterHeader.evaluate().isNotEmpty) {
      await tester.ensureVisible(filterHeader.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(filterHeader.first);
      // ExpansionTile animation runs ~200ms. Pump a generous window so
      // the expanded body is fully laid out before screencap.
      await tester.pump(const Duration(milliseconds: 600));
      await _capture(binding, tester, '02-home-filters');
      // Collapse the panel before navigating away so the next surface
      // (Title Detail) doesn't re-open onto a partially-animated state.
      await tester.tap(filterHeader.first);
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      debugPrint(
          'WN_SS skip 02 — "Filter recommendations" header not found');
    }

    // ── 3) Title Detail (Tonight's Pick) ───────────────────────────────
    // The Tonight's Pick hero card has two tap targets — the poster InkWell
    // and a "Let's watch this" FilledButton — both call
    // `context.push('/title/<mediaType>/<tmdbId>')`. The button label is
    // unique on Home + reliable to find.
    final watchCta = find.text("Let's watch this");
    if (watchCta.evaluate().isNotEmpty) {
      await tester.ensureVisible(watchCta.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(watchCta.first);
      await tester.pump(const Duration(milliseconds: 400));
      // TitleDetail does a parallel TMDB fetch for movieDetails / tvDetails
      // + external_ids + reviews + similar carousel + trailer. Most of
      // these render placeholders first then fill in. Give the network +
      // image loads ~6s to settle so the screenshot shows a fully-loaded
      // detail screen, not a half-loaded one.
      await tester.pump(const Duration(seconds: 6));
      await _capture(binding, tester, '03-title-detail');
      // Back to Home before the next nav step. TitleDetailScreen's
      // AppBar renders a plain `IconButton(Icons.arrow_back)` with no
      // tooltip (see title_detail_screen.dart:611-615) so `find.byIcon`
      // is the reliable handle — `find.byTooltip('Back')` won't match.
      // Multiple Icons.arrow_back may exist if a child Stremio/IMDb
      // popup is open; `.first` lands on the AppBar one since it's
      // earliest in the widget tree.
      final backBtn = find.byIcon(Icons.arrow_back);
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn.first);
      } else {
        // Fall back to the system back gesture.
        await tester.pageBack();
      }
      await tester.pump(const Duration(milliseconds: 600));
    } else {
      debugPrint('WN_SS skip 03 — "Let\'s watch this" CTA not found');
    }

    // ── 4) Library tab ─────────────────────────────────────────────────
    // LiquidNavBar exposes 3 destinations, semantic labels Home / Library /
    // Profile (see lib/app.dart's ScaffoldWithNavBar). Each Semantics node
    // is keyed `${label}-${selected}` — selected swaps the icon outlined →
    // filled. The unselected node's key is e.g. `Library-false`, which is
    // the unambiguous handle when we're navigating from Home.
    final libraryNav = find.byKey(const ValueKey('Library-false'));
    if (libraryNav.evaluate().isNotEmpty) {
      await tester.tap(libraryNav.first);
      await tester.pump(const Duration(milliseconds: 500));
      // Library's Saved tab streams watchlist items + their TMDB poster
      // paths — give the row images time to land.
      await tester.pump(const Duration(seconds: 4));
      await _capture(binding, tester, '04-library');
    } else {
      debugPrint('WN_SS skip 04 — Library nav destination not found');
    }

    // ── 5) Profile tab ─────────────────────────────────────────────────
    // Same selector pattern as Library. Lower priority capture; this is
    // mostly useful as a "preferences page" surface to demonstrate the
    // app icon picker / accent picker / mode toggle defaults.
    final profileNav = find.byKey(const ValueKey('Profile-false'));
    if (profileNav.evaluate().isNotEmpty) {
      await tester.tap(profileNav.first);
      await tester.pump(const Duration(milliseconds: 500));
      // Profile reads a few Firestore docs (member display name, badges)
      // — short settle window.
      await tester.pump(const Duration(seconds: 3));
      await _capture(binding, tester, '05-profile');
    } else {
      debugPrint('WN_SS skip 05 — Profile nav destination not found');
    }
  });
}

/// Waits up to ~25s for the Home screen's "TONIGHT'S PICK" section label to
/// appear. That label is rendered by `_SectionLabel("TONIGHT'S PICK")` in
/// `home_screen.dart` and only exists once the household's Firestore stream
/// has resolved AND tonightsPick is non-null — a reliable "Home has data"
/// signal. Pumps in 500ms ticks so we don't capture earlier than necessary.
///
/// Falls through silently after the timeout — the test still proceeds to
/// the first capture, which will at least show whatever state the app is
/// in and surface diagnostics in the workflow artifact.
Future<void> _waitForHomeSettled(WidgetTester tester) async {
  const tick = Duration(milliseconds: 500);
  const budget = Duration(seconds: 25);
  final deadline = DateTime.now().add(budget);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(tick);
    if (find.text("TONIGHT'S PICK").evaluate().isNotEmpty) {
      // One more pump pass to let the poster Image.network calls land.
      await tester.pump(const Duration(seconds: 6));
      return;
    }
  }
  debugPrint('WN_SS Home settle window elapsed without finding TONIGHT\'S PICK');
}

/// Captures a screenshot via the integration_test binding. The bytes are
/// auto-pushed into `binding.reportData['screenshots']` as a list of
/// `{screenshotName, bytes}` maps; the host-side
/// `test_driver/integration_test.dart` runner picks them up via the
/// driver channel and writes PNGs to `screenshots/it/` on the runner.
///
/// Wrapped in try/catch because a single failed capture shouldn't kill
/// the rest of the sweep — we'd rather have 4 of 5 surfaces than 0.
Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  // Give the current frame one more chance to fully render before the
  // surface read. Without this the first capture per session sometimes
  // returns a partially-laid-out frame.
  await tester.pump(const Duration(milliseconds: 250));
  try {
    await binding.takeScreenshot(name);
    debugPrint('WN_SS captured $name');
  } catch (e) {
    debugPrint('WN_SS capture failed for $name: $e');
  }
}
