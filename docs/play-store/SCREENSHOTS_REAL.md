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

### 2. Add four GitHub secrets

Repo → Settings → Secrets and variables → Actions → "New repository secret":

| Secret name                     | Value                                                                                                                                                                                                                                                                                                  |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Raw contents of the JSON file from step 1. Paste the whole `{...}` object. Don't add a trailing newline.                                                                                                                                                                                              |
| `GOOGLE_SERVICES_JSON_B64`      | `base64 -w0 android/app/google-services.json` — the same one used locally + by the existing release workflow. Use `-w0` so the encoded string has no embedded line breaks.                                                                                                                            |
| `TMDB_API_KEY`                  | Same v3 TMDB key already in `env.json` locally. The seed doesn't call TMDB, but the app does — without this, posters are blank in the screenshots.                                                                                                                                                    |
| `TRAKT_CLIENT_ID`               | Same client id already in `env.json`. The app validates the dart-define at startup; an empty value would crash on the splash screen even though the screenshot run never actually opens the Trakt OAuth flow.                                                                                          |

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
