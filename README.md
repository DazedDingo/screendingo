<p align="center">
  <img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="128" alt="ScreenNext app icon"/>
</p>

# ScreenNext

**A shared movie & TV companion for two-person households.**
Decide what to watch — *together* — with recommendations that learn from both partners' taste.

[![Latest release](https://img.shields.io/github/v/release/DazedDingo/watchnext?label=latest&color=E50914)](https://github.com/DazedDingo/watchnext/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#install)
[![Built with Flutter](https://img.shields.io/badge/Flutter-3.11+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Material 3](https://img.shields.io/badge/Material%203-Dark-6750A4)](https://m3.material.io)

---

## Install

Head to the [**latest release**](https://github.com/DazedDingo/watchnext/releases/latest), download the `.apk` asset, and open it on your Android phone.

> **First time?** You may need to allow your browser to install apps from unknown sources. Once installed, upgrades just work — every new APK preserves your Trakt login, settings, and household data.

Each release comes with a short *What's new* so you always know what you're getting.

---

## What can it do?

### 🎬 Finding something to watch

- **Tonight's Pick** — one hero suggestion on the Home screen, chosen from a taste-scored pool refreshed every time you pull to refresh.
- **Upcoming for you** — a carousel of movies and TV about to release, ranked by how well they match your household's genre mix.
- **Discover** — browse Trending, New Releases, or any TMDB genre.
- **"Surprise me"** — random pull from the top of your rec list for when nothing's landing.
- **"More like these"** — pick 2–8 titles you love, the AI concierge suggests films that fit the group as a whole.
- **Live search** — find anything on TMDB from the Home search bar.

### 🧑‍🤝‍🧑 Deciding together

- **Decide** — each partner gets their top 5. Side-by-side. Tap to match, compromise, veto, or break a tie.
- **"Surprise me"** inside Decide fishes an older decade from TMDB when the trending pool feels stale.
- **Predict & Rate** — both partners secretly guess a 1–5 star rating *before* watching; afterwards a Reveal screen shows who called it closer.
- **Concierge chat** — a proper chat with an AI that knows your history, watchlist, ratings, and household context. Tap any suggestion to open the title.

### 📚 Tracking what you watch

- **Watchlist** — shared queue plus solo queues for personal watches. A dedicated *Watching* tab for TV shows in progress.
- **History** — Watched, In progress, and Unrated tabs. Swipe to rate.
- **Title detail** — metadata, similar titles, AI blurb, household ratings, watchlist + watch-status controls, inline trailer, **IMDb / Rotten Tomatoes / Metascore** ratings inline, an expandable **Reviews** section, and deep links to Stremio, IMDb, and Letterboxd.
- **Watch status for TV** — *Not / Watching / Watched*, so "I'm halfway through" is a real state.

### 🏆 Stats & streaks

- Compatibility %, top genres per person, rating distributions.
- **Watch streaks** and **rating streaks** — with a flame 🔥 once you hit three days.
- **12 badges** — First Watch, Century Club, Genre Explorer, Binge Master, Marathon Mode, Compromise Champ, Show Finisher, Perfect Sync, Prediction Machine, Five-Star Fan, Critic, Tagger. You get a push notification the moment one unlocks.

### 🎨 Your look

- Pick an **accent colour** from 18 named seeds — the whole app recolours instantly. Default is the Streaming red.
- **Dark-only** Material 3 theme.
- Animated *Screen**Next*** wordmark on the title bar, splash, and login.

---

## What makes it ours

### Solo vs Together

Every surface — recommendations, predictions, stats, watchlists — respects a segmented **Solo ↔ Together** toggle at the top of the screen. Your tastes as a household and your tastes alone are tracked separately, so a Saturday-night horror binge for one doesn't drown out the comfort shows you share.

### Integrations

- **Trakt** — per-user OAuth. One-time full sync pulls your entire watch history, then incremental syncs keep things current. Ratings push both ways.
- **Stremio** — Profile → Stremio generates a private install URL that exposes your shared watchlist as a Stremio catalog.
- **Android share sheet** — hit "Share" from IMDb, Letterboxd, Google, or any browser and ScreenNext offers to save the title straight to your watchlist.

---

## Is this for you?

- You live with one other person. (Hard-coded two-person household — by design.)
- You're on **Android**. iOS isn't planned.
- You'd like to self-host the backend or build from source. (There's no hosted version — this is a personal project; read more below.)

---

## Want to see where it's heading?

See [**ROADMAP.md**](ROADMAP.md) for the full phase-by-phase build plan — what's shipped, what's in progress, and what's still on the wishlist.

---

## For developers

<details>
<summary><strong>Architecture & tech stack</strong></summary>

| Layer | Tech |
|-------|------|
| Frontend | Flutter 3.11+ (Dart), Material 3 dark |
| State | Riverpod 2.5 |
| Routing | go_router 14.2 |
| Backend | Firebase Auth, Firestore, Cloud Functions (`europe-west2`), Cloud Messaging |
| Cloud Functions | Node 22 TypeScript, firebase-admin 13 |
| AI | Google Gemini 2.5 Flash (free tier, 1,500 req/day) — batch scoring + concierge chat |
| Movie data | TMDB |
| Watch tracking | Trakt (OAuth 2.0) |

**Project structure:**

```
lib/
  screens/     # Every screen — auth, home, discover, watchlist, history,
               # stats, profile, title_detail, decide, reveal, predict,
               # like_these, concierge, rating, share_confirm
  providers/   # Riverpod state — mode, household, ratings, recommendations,
               # stats, trakt, filters, theme
  services/    # API wrappers — auth, household, trakt, tmdb, recommendations,
               # rating, watch_entry, share_parser, concierge, notification
  models/      # WatchEntry, Rating, Recommendation, Prediction, Decision, …
  widgets/     # Shared UI components

functions/src/ # Cloud Functions — concierge, scoreRecommendations,
               # tasteProfile, stremio, redditScraper, notifications,
               # gamificationUpdater, submitIssue, rescoreRecommendations

test/          # 555 Dart tests (unit, widget, routing, rules, fuzz)
test-rules/    # 43 Firestore security-rules E2E tests
```

For the architecture deep-dive, known gotchas, and conventions, see [`CLAUDE.md`](CLAUDE.md).

</details>

<details>
<summary><strong>Running locally</strong></summary>

**You'll need:**

- Flutter SDK (^3.11)
- A Firebase project with Auth, Firestore, Cloud Functions, and Messaging enabled
- A TMDB API key
- A Trakt application (redirect URI `com.household.watchnext://trakt-callback`)
- A Gemini API key (free at https://aistudio.google.com/apikey)

**Setup:**

1. Drop `google-services.json` into `android/app/`.
2. Regenerate `lib/firebase_options.dart`:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<your-firebase-project-id>
   ```
3. Set your project id in `.firebaserc`.
4. Copy `env.example.json` → `env.json` (gitignored) and fill in:
   ```json
   {
     "TMDB_API_KEY": "…",
     "TRAKT_CLIENT_ID": "…",
     "TRAKT_CLIENT_SECRET": "…"
   }
   ```
5. Push your Cloud Functions secrets:
   ```bash
   firebase functions:secrets:set TRAKT_CLIENT_SECRET
   firebase functions:secrets:set GEMINI_API_KEY
   firebase functions:secrets:set TMDB_API_KEY
   ```

**Run:**

```bash
./run.sh        # wraps flutter run with --dart-define-from-file=env.json
```

**Test:**

```bash
./test.sh       # full matrix — analyze + Dart tests + tsc + eslint + jest + rules
flutter test    # Dart tests only
```

**Deploy Cloud Functions & rules:**

```bash
firebase deploy --only firestore:rules
cd functions && npm install && cd ..
firebase deploy --only functions
```

</details>

<details>
<summary><strong>Security model</strong></summary>

- Every Firestore read and write is scoped to verified household membership (`isMember(householdId)`).
- Two-person cap enforced at service level (`HouseholdService.joinByInviteCode`).
- Admin-SDK-only collections: `/stremioTokens`, `/rescoreQueue`, `/issueBatches`, `/households/{hh}/badges`.
- Rules live in [`firestore.rules`](firestore.rules); a 43-test E2E suite in [`test-rules/`](test-rules/) exercises them against the emulator.
- Trakt refresh tokens encrypted at rest on the member doc; `client_secret` lives only in Firebase Secrets Manager.
- Android signing pinned to `android/app/debug.keystore`; CI fails loudly if the APK's SHA-1 drifts from the Firebase-registered cert.

</details>

---

## License

© 2026 Zachary Birney, trading as [DazedDingo](https://github.com/DazedDingo). All rights reserved — see [`LICENSE`](LICENSE), [Privacy](docs/PRIVACY.md), [Terms](docs/TERMS.md). Both docs are served at `dazeddingo.github.io/watchnext/PRIVACY` and `.../TERMS` once GitHub Pages is enabled on `docs/`.

---

## Publishing to Google Play (release-prep checklist)

The sideload APK pipeline above is unchanged — every push to `main`
still builds a debug-signed APK and attaches it to a GitHub Release for
quick install and field-debug. The Play track is a parallel,
manually-triggered build (`.github/workflows/release-aab.yml`) and ships
the **same code** signed with a separate upload key. Keep both around so
you can debug against a build that matches the Play release.

### One-time setup (off-repo)

1. **Generate the upload keystore.** Keep it offline — losing it means
   you can never update your Play listing again.

   ```bash
   keytool -genkey -v -keystore watchnext-upload.jks \
     -alias watchnext-upload \
     -keyalg RSA -keysize 2048 -validity 10000
   base64 -w 0 watchnext-upload.jks > watchnext-upload.b64
   ```

2. **Add four GitHub secrets** (Settings → Secrets and variables →
   Actions):
   - `UPLOAD_KEYSTORE_B64` — contents of `watchnext-upload.b64`
   - `UPLOAD_KEYSTORE_PASSWORD` — keystore password
   - `UPLOAD_KEY_ALIAS` — `watchnext-upload`
   - `UPLOAD_KEY_PASSWORD` — key password (usually same as keystore)

3. **Enable Firebase App Check** (Firebase console → App Check →
   register the Android app with Play Integrity provider, then enable
   enforcement on shipped Cloud Functions). Blocks reverse-engineered
   clients from spending your Gemini quota.

4. **Set Cloud Billing alerts** (GCP Console → Billing → Budgets &
   alerts → $1 / $5 / $20). Catches runaway spend before it's a wallet
   event.

5. **Trademark sanity-check "ScreenNext"** on USPTO TESS / EUIPO eSearch
   before publishing — generic name, confirm nobody's already filed in
   the entertainment-software class.

6. **Register a Google Play developer account** ($25 one-time + ID
   verification). Legal name on file, brand "DazedDingo" as the
   developer display name.

### Per-release flow

1. Push to `main` as usual → debug APK gets released for sideload
   testing.
2. When ready to ship to Play, fire the `release-aab` workflow manually
   (Actions tab → "release-aab (Play upload bundle)" → Run workflow).
3. Download the AAB artifact from the workflow run page.
4. Upload to Play Console (Internal testing → Production track when
   stable). The 14-day, 20-tester closed-test requirement applies only
   to brand-new apps; once you're past it, updates roll out directly.

### Cost protection

The Cloud Functions that spend metered third-party quota have per-user
daily caps (see [`functions/src/rateLimit.ts`](functions/src/rateLimit.ts)):

- `concierge`: 50 chat / Like-these messages per user per 24h
- `scoreRecommendations`: 30 refreshes per user per 24h

Generous for real households, tight enough that one abusive client
can't burn the shared Gemini free tier. Counters live at
`/userRateLimits/{uid}` (admin-SDK only).
