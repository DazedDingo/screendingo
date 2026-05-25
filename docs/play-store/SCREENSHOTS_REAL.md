# Screenshots — real-Firebase pipeline

The `screenshots-real.yml` GitHub Actions workflow builds the production app
against a curated "screenshot test household" pre-seeded in real Firestore,
then captures Play-Store-ready screenshots on a Pixel emulator. Unlike the
older `screenshots.yml` pipeline (which exercises DEMO_MODE + mocked
providers), this one runs the actual app end-to-end: real Firebase Auth,
real Firestore listeners, real Cloud Function calls, real TMDB poster + AI
blurb rendering.

## One-time setup

### 1. Mint a service account

Firebase Console → Project Settings → Service accounts → "Generate new
private key". Download the JSON. The account needs:

- **Firebase Authentication Admin** — for `createCustomToken`
- **Cloud Datastore User** (or higher) — for the seed write

You can grant these via Google Cloud Console → IAM if the default
service-account role isn't sufficient.

### 2. Add the one new GitHub secret

Three of the four secrets the workflow needs are already set on the
repo from earlier work (`GOOGLE_SERVICES_JSON`, `TMDB_API_KEY`,
`TRAKT_CLIENT_ID` — verify with `gh secret list`). Only one is new:

Repo → Settings → Secrets and variables → Actions → "New repository secret":

| Secret name                     | Value                                                                                                                                                                                                                                                                                                  |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Raw contents of the JSON file from step 1. Paste the whole `{...}` object. Don't add a trailing newline.                                                                                                                                                                                              |

Faster path if you have `gh` CLI authenticated:

```bash
gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < /path/to/serviceAccount.json -R DazedDingo/screendingo
```

(Pipes the file in via stdin, no newline gymnastics. Verify with
`gh secret list -R DazedDingo/screendingo`.)

### 3. (Optional) Run the seed once locally to verify

```bash
cd functions
export GOOGLE_APPLICATION_CREDENTIALS=/abs/path/to/serviceAccount.json
npx ts-node scripts/screenshots_setup.ts seed
```

Expected output:

```
Seeding 35 docs into household demo_household_1…
OK — 35 docs written.
```

You can inspect the result in Firebase Console → Firestore → `households/demo_household_1/`. You should see `members/`, `recommendations/`, `ratings/`, `watchEntries/`, `watchlist/`, `notInterested/`, `tonightsPick/current`, and `tasteProfile/current` populated.

## Triggering a screenshot capture

Repo → Actions → "screenshots-real (Play Store)" → "Run workflow". No
inputs required; it picks up `main`. The run takes ~5 minutes:

1. ~30s — Setup + dependency installs
2. ~30s — Seed Firestore (re-seeds every run so timestamps stay fresh)
3. ~1m — Build the debug APK
4. ~3m — Boot emulator, install, capture progressive screencaps at t=5s,
   15s, 30s, 45s, 60s, plus a logcat diagnostics bundle

Artifact is named `screendingo-screenshots-real` and contains the five PNGs
plus the diagnostics. Download from the run page.

## How the pipeline works

The flow has three load-bearing pieces:

1. **`functions/scripts/screenshots_setup.ts`** has two subcommands:
   - `seed` — writes the curated household to Firestore. Idempotent
     (`set` everywhere — no `add`), so re-running just refreshes the
     same docs. The data set mirrors `lib/demo/demo_data.dart` so DEMO_MODE
     and real-Firebase screenshot runs render the same household.
   - `mint-token` — calls `getAuth().createCustomToken(VIEWER_UID)` and
     prints the token to stdout. The workflow captures the print and
     bakes it into the APK via `--dart-define=AUTO_SIGN_IN_TOKEN=...`.
     Tokens last ~1h (custom-token TTL); the resulting session lives
     well beyond the screenshot run.

2. **`lib/main.dart`** reads `_kAutoSignInToken` at startup via
   `String.fromEnvironment`. Empty token (normal builds) → no
   auto-sign-in, router falls through to `/login` as it always has.
   Non-empty → `FirebaseAuth.instance.signInWithCustomToken(token)`
   runs after App Check activation, and the router lands directly on
   `/home` with the pre-seeded household visible.

3. **The seeded uid is the same `kDemoUid` constant** used by DEMO_MODE
   (`demo_uid_alex` / `demo_household_1` / `demo_uid_jamie`). Re-using
   these means we can swap freely between the two pipelines without
   maintaining parallel data sets.

## Refreshing the seed content

Edit the seed payloads in `functions/scripts/screenshots_setup.ts`
(`recommendations`, `watchEntries`, `ratings`, `watchlist`,
`notInterested`, `tonightsPickDoc`, `tasteProfile`). The schema mirrors
each model's `toFirestore()` map — snake_case field names.

Keep `lib/demo/demo_data.dart` and `screenshots_setup.ts` in sync so
DEMO_MODE and screenshots-real render the same household. When changing
both, mirror each title's poster path / ai blurb / match score across the
two files.

## Cost

Per CI run:

- ~35 Firestore writes (seed) + a handful of session-related Auth writes
- ~50–100 Firestore reads + ~5 Cloud Function invocations + ~20 TMDB
  calls (app on the emulator settling)
- All well within the Firebase / TMDB free tiers — no cost flag.

The token mint itself is free (Firebase Auth's `createCustomToken` is
self-signed via the service account, no network round-trip).

## Variant: integration_test driver (`screenshots-real-it.yml`)

`screenshots-real.yml` captures Home only — every frame is the same
Tonight's Pick + rec list. For Play Store listings that need 4–8
distinct surfaces we have a second workflow,
`screenshots-real-it.yml`, that drives an integration_test through the
running app between captures.

**What it captures**:

1. `01-home.png` — Home with Tonight's Pick + Recommended-for-you fully rendered
2. `02-home-filters.png` — Home with the "Filter recommendations"
   expansion panel open (showing the genre / sub-topic / runtime / year /
   awards / curator knobs)
3. `03-title-detail.png` — Title Detail for Tonight's Pick (tapped via
   "Let's watch this"), with poster + AI blurb + external ratings +
   action row visible
4. `04-library.png` — Library tab (Saved sub-tab default), watchlist
   rows visible
5. `05-profile.png` — Profile tab (lower priority — useful as a
   "preferences page" surface)

**When to prefer it over `screenshots-real.yml`**:

- Need variety for a Play Store listing refresh — same data set, but
  the app navigates between surfaces between captures.
- Want to validate a UI change end-to-end on real Firebase + TMDB
  without manually clicking through on a device.

**When to fall back to `screenshots-real.yml`**:

- The integration_test driver hangs or fails to boot in the emulator.
  The adb-screencap path is the proven Home-only fallback.
- You only need a refreshed Home screenshot (e.g. after a Tonight's
  Pick logic change) — the adb pipeline is faster + simpler for that
  case.

**How to trigger**:

```bash
gh workflow run "screenshots-real-it (Play Store)" -R DazedDingo/screendingo
```

Or via the GitHub UI: Repo → Actions → "screenshots-real-it (Play
Store)" → "Run workflow". No inputs required. Run takes ~7–10 minutes
(longer than the adb path because `flutter drive` builds both an app
APK and a test APK and runs the device-side test interactively).

Artifact name is `screendingo-screenshots-real-it`. Same crop pipeline
as the adb path — final Play-safe PNGs land under `processed/` inside
the artifact at 1080×1920.

**Required secrets**: same set as `screenshots-real.yml` —
`GOOGLE_SERVICES_JSON`, `FIREBASE_SERVICE_ACCOUNT_JSON`,
`TMDB_API_KEY`, `TRAKT_CLIENT_ID`. No new secrets to provision.

**How the driver works**: the device-side test
(`integration_test/screenshots_test.dart`) boots `app.main()`, polls
for the seeded Home to render, then navigates between surfaces and
calls `binding.takeScreenshot('beat-name')` between each. The bytes
travel up the test driver channel to the host runner
(`test_driver/integration_test.dart`) which writes PNGs under
`screenshots/it/<beat>.png`. The workflow then copies them up to
`screenshots/` so `process_screenshots.py` finds them with the same
glob the adb path uses.
