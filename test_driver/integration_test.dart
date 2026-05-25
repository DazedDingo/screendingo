// Host-side runner for `integration_test/screenshots_test.dart`.
//
// `flutter drive --driver=test_driver/integration_test.dart --target=...`
// launches this file on the host (the CI runner). It opens a driver
// channel to the device-side test, waits for it to finish, then receives
// the `reportData` map back via `response.data`. The integration_test
// SDK auto-stamps every `binding.takeScreenshot(name)` call into
// `reportData['screenshots']` as `[{screenshotName, bytes}]`, and the
// `integrationDriver()` helper iterates that list + calls our
// `onScreenshot` callback once per entry. We just decode + write the
// PNG bytes to `screenshots/it/<name>.png` on the host filesystem,
// where the next workflow step finds them.
//
// This is the documented driver-extended pattern from the
// `integration_test` package — see `integration_test_driver_extended.dart`
// in the Flutter SDK source for the canonical example. Doing it this way
// (instead of writing PNGs from inside the device-side test via dart:io)
// means we don't need any storage permission on the device + the bytes
// never touch the device's filesystem.

import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  // Output dir is `<repo>/screenshots/it/` so it doesn't collide with the
  // adb-screencap pipeline's `<repo>/screenshots/` PNGs when both
  // workflows run in the same checkout (rare, but the directory split
  // keeps the artifact layouts unambiguous when triaging which pipeline
  // captured what).
  final outDir = Directory('screenshots/it');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  await integrationDriver(
    // Called once per `binding.takeScreenshot(...)` invocation on the
    // device side. Bytes arrive as `List<int>` (the SDK ferries raw bytes
    // across the driver channel without compression). Returning `true`
    // tells the SDK the screenshot was processed successfully; returning
    // `false` would cause `integrationDriver` to fail the run, which is
    // not what we want — a failed file-write should warn, not abort the
    // whole sweep when other captures succeeded.
    onScreenshot: (String name, List<int> bytes, [_]) async {
      try {
        final path = '${outDir.path}/$name.png';
        File(path).writeAsBytesSync(bytes);
        stdout.writeln('Wrote $path (${bytes.length} bytes)');
        return true;
      } catch (e) {
        stderr.writeln('Failed to write screenshot $name: $e');
        // Returning true so a single bad file-write doesn't abort the
        // remaining captures. The artifact will still surface the
        // captures that DID land.
        return true;
      }
    },
    // Even if some screenshots fail upstream, the device-side test may
    // still report individual test failures. `writeResponseOnFailure`
    // ensures the responseDataCallback runs so we can grab whatever
    // metadata the failure produced. Default is `false` — flipping it
    // here so a partial run still yields a populated reportData JSON
    // file in test_outputs/.
    writeResponseOnFailure: true,
  );
}
