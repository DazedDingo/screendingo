# ScreenDingo — Play Store listing copy

Draft of every text field you'll paste into Play Console's "Main store
listing" + "Data safety" + "Content rating" forms. Edit to taste before
publishing — the privacy/data fields below are mechanically derived from
the codebase and should be accurate as of v0.10.7.

---

## App title (30 chars max)

```
ScreenDingo: Couples Movie Picks
```

Alt options:
- `ScreenDingo — Movies for Two` (26)
- `ScreenDingo: Pair Watch Picks` (27)

## Short description (80 chars max)

```
A shared movie + TV picker for two — learns from both your tastes.
```

Alt:
- `Find what you'll both love. A movie + TV recommender built for two.` (66)
- `Stop scrolling Netflix forever. Movie + TV picks tailored to both of you.` (72)

## Full description (4000 chars max)

```
ScreenDingo is a movie + TV recommendation app built specifically for
two-person households. Sign in, pair with your partner, rate a few
titles, and start getting picks that reflect what BOTH of you would
actually enjoy — not just what one of you likes and the other tolerates.

— FEATURES —

• Shared library — your watchlist, watch history, and ratings sync
  with your partner in real time across both phones.

• Smart recommendations — AI-powered scoring that learns from your
  combined taste profiles. New picks every refresh, narrowed by genre,
  year, runtime, awards, curator (A24 / Neon / Ghibli / Searchlight),
  or sub-topic (animal docs, slasher, cyberpunk, heist, and 60+ more).

• Solo & Together modes — toggle between "just me" mode (filters to
  your personal taste) and "together" mode (the shared compromise
  pick) without leaving the household.

• Decide for me — when you can't agree, the Decide screen alternates
  picks from the watchlist until someone says yes.

• Tonight's Pick — one curated suggestion at the top of Home, refreshed
  daily based on what you'd both rate ≥4.

• Up Next — episodic shows you're mid-season on, with next-episode
  notifications so you don't miss new airs.

• Predict & Reveal — guess what your partner would rate a title; the
  Prediction Machine tracks who's better at reading the other's
  taste.

• Concierge chat + "More like these" — describe what you're in the
  mood for ("a slow-burn psychological thriller from the 70s") or
  hand-pick a group of seed titles and get LLM-curated suggestions.

• Trakt sync (optional) — link your Trakt account to sync watch
  history and ratings across services.

• Stremio addon — install the ScreenDingo catalog inside Stremio to
  surface your shared watchlist directly in your streaming app.

• Home-screen widget — "Up Next" tile shows the three closest-to-air
  episodes without opening the app.

• 12 unlockable badges — Century Club, Genre Explorer, Marathon Mode,
  Perfect Sync, and more. Earn them together or individually.

— PRIVATE AND COUPLE-SCALED BY DESIGN —

ScreenDingo was built for two people, not millions. There's no social
feed, no friend graph, no "trending in your city". Every Firestore
collection is scoped to your household — your partner is the only
other person who can see your ratings.

We don't run third-party ads or analytics SDKs. Your watch history
isn't sold or licensed. Trakt linking is opt-in and revocable from
the in-app Profile screen.

— BUILT BY DAZEDDINGO —

ScreenDingo is a personal project, built and maintained by Zachary
Birney (trading as DazedDingo). Source code, release notes, and the
issue tracker are public at
github.com/DazedDingo/watchnext. Privacy policy and terms are
linked from the Play listing.
```

(currently ~2,000 characters — room to add screenshots / testimonials
or trim the feature list. Don't keyword-stuff: Play's algorithm
penalises descriptions that read as SEO copy.)

---

## Category & tags

**Primary category**: Entertainment

**Tags** (Play Console picks up to 5):

- Movies & TV
- Recommendations
- Couples / Partner apps
- Watchlist
- TV Tracker

---

## Content rating questionnaire (IARC)

Most answers are "No" — the app is non-violent, non-sexual, non-gambling.
The only nuance: it surfaces ratings/posters/synopses for adult-rated
movies and TV shows. Answers:

| Question | Answer |
|---|---|
| References to or depictions of violence | No (we display third-party metadata, never depict it ourselves) |
| Sexual content or nudity | No |
| Strong language | No (only what's in TMDB-supplied movie titles, which is mild) |
| Controlled substances | No |
| Gambling content | No |
| User-generated content shared with others | Yes — your partner sees your ratings and notes |
| User-to-user interaction | Yes — pairing with partner |
| Shares user location | No |
| Allows users to purchase items | No (in-app purchases — N/A unless added later) |

Expected rating: **Everyone (PEGI 3 / ESRB Everyone)**.

---

## Data safety form

This is the form Google scrutinises hardest. Answers mechanically
derived from the codebase as of v0.10.7.

### Data collection summary

**Personal info**:
- Name (collected, shared with no one, optional, NOT for ads or analytics)
- Email (collected via Google Sign-In, NOT shared, NOT for ads)
- User ID (Firebase Auth uid; collected, NOT shared, NOT for ads)

**App activity**:
- App interactions (ratings, watchlist actions; collected, shared with
  Trakt IF user opts in, NOT for ads)
- In-app search history (concierge chat history; collected, NOT
  shared, NOT for ads)

**App info and performance**:
- Crash logs (Firebase Crashlytics — N/A unless added)
- Diagnostics (none beyond Firebase Auth tokens)

**Messages**:
- Other in-app messages (concierge chat is between user and Gemini;
  partner does NOT see chat history)

**Photos and videos**:
- None collected

**Files and docs**:
- None collected

**Audio**:
- None collected

**Contacts**:
- None collected

**Location**:
- None collected

**Web browsing**:
- None collected

**Health and fitness**:
- None collected

**Financial info**:
- None collected (no IAP, no payment data)

### Data sharing summary

| Recipient | Data shared | Purpose |
|---|---|---|
| Google Firebase | Account info, ratings, watchlist, taste profile, chat history | Backend hosting + AI scoring |
| TMDB | Movie/TV title IDs (no account info) | Metadata lookup |
| Trakt (opt-in) | Ratings + watch history | Two-way sync |
| Google Gemini | Genre tags + seed titles (no account info) | AI recommendations + chat |
| OMDb | IMDb IDs of titles viewed (no account info) | Critic-score lookup |
| Reddit | Public title queries (no account info) | Social-proof data |

### Security practices

- ✅ Data is encrypted in transit (HTTPS for all API calls)
- ✅ You can request that data be deleted (in-app + email request)
- ✅ Data deletion takes ≤30 days
- ✅ Independent security review: **No** (small personal-use app)

---

## Screenshots brief (8 max, recommend 5)

Capture from a Pixel 8 (Play Console's preferred reference device) in
portrait mode, both Solo and Together modes, with a populated household:

1. **Home feed** — Tonight's Pick + the recommendation list. Caption:
   "Picks that work for both of you."
2. **Filter panel expanded** — show genre + sub-topics + the new 2-col
   awards/curated row + Reset all. Caption: "Narrow the pool — by
   genre, length, era, awards, curator, or sub-topic."
3. **Title detail** — poster + trailer button + ratings + IMDb/Stremio
   buttons. Caption: "Everything you need to decide, on one screen."
4. **Decide screen** — the alternating pick UI. Caption: "Can't agree?
   The Decide screen alternates until someone says yes."
5. **Library tab** — Saved / Watching / Watched / Unrated. Caption:
   "Your shared library, always in sync."

Optional 6-8:
6. Profile insights (badges + stats)
7. Concierge chat ("More like these" result)
8. Up Next widget on home screen

## Feature graphic

1024 × 500. Recommend the "Screen**Dingo**" wordmark (gradient sweep on
"Next") centred on a dark background, with a 2x4 grid of stylised
poster outlines fading into the background. No screenshot — Play
penalises feature graphics that duplicate screenshot content.

## App icon

Already exists at `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
(512x512). Use this — the 5 alternate launcher icons in the picker
(Classic, Vivid, Minimal, Clapper, Cream) are post-install user choices
and don't affect the Play listing icon.

## Promo video (optional)

15-30s screen capture showing: open app → tap Tonight's Pick → poster
fades in → swipe to Discover → tap a title → trailer plays inline.
Score with a copyright-clear bed track from YouTube Audio Library.

---

## Pricing

If launching as paid up-front: $1.99 USD is the price point most
indie utility-style apps land on. Higher (>$3) requires either a known
brand or a unique value prop. Below $0.99 most users don't differentiate
from free.

If free + IAP / subscription: requires `in_app_purchase` package
integration + receipt verification (not currently shipped). Defer.

If free + ads: requires `google_mobile_ads` (AdMob) — adds a privacy
disclosure obligation and the per-impression ad-tracking SDK note.
Skip; the app is small enough that ads would degrade UX more than
they'd earn.

---

## Pre-launch checklist

- [ ] All four GitHub secrets set (`UPLOAD_KEYSTORE_*`)
- [ ] AAB workflow succeeds locally — download artifact, verify signed
      with the upload keystore (Play Console will reject mismatched
      certs)
- [ ] Privacy policy hosted at a public URL (GitHub Pages of
      `PRIVACY.md` is fine: `dazeddingo.github.io/watchnext/PRIVACY`)
- [ ] Terms of service hosted at a public URL
- [ ] App Check enabled + enforcement on shipped Cloud Functions
- [ ] Cloud Billing alerts configured ($1, $5, $20)
- [ ] Trademark search done for "ScreenDingo" + "DazedDingo"
- [ ] Developer account verified (legal name + government ID on file
      with Google)
- [ ] 20 testers identified for the closed-test window
- [ ] Data Safety form completed (this doc has the answers)
- [ ] Content rating questionnaire completed (this doc has the answers)
- [ ] Screenshots captured (5–8 portrait, see brief above)
- [ ] Feature graphic designed (1024 × 500)
- [ ] App description copy reviewed (this doc)
- [ ] Pricing decided (this doc has the analysis)
- [ ] First production push triggered via Internal → Closed → Open →
      Production
