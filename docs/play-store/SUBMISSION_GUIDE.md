# ScreenDingo — Play Console submission guide

What to paste into each Play Console form field, in submission order.
Generated 2026-05-25; values cross-checked against `LISTING.md`, the
upload keystore, the Firebase project, and the live GitHub Pages
hosting at `https://dazeddingo.github.io/screendingo/`.

---

## ⚠ Blocker before submission

`docs/PRIVACY.md` line 10 leaves the developer postal address as
`(A postal address will be added before the Play listing goes live)`.
**Play Console requires a verified physical address** on the developer
account AND on the privacy policy — without it, GDPR Article 13
compliance fails and the listing will be rejected on the
"Developer account → Account details" review step.

Three options:

1. **Use your home address** — fastest, no monthly cost, but it'll be
   visible on the Play listing forever (Play surfaces the developer
   address publicly under "Developer contact info").
2. **Rent a virtual mailbox** — services like Anytime Mailbox or
   iPostal1 are ~$10/mo and give you a real street address (Google
   rejects P.O. boxes).
3. **Use a registered agent service** — typical $50–150/yr; usually
   what people pick if they want to keep their home address private.

Update `docs/PRIVACY.md` line 10 with the address you go with, push,
wait for Pages to redeploy (~90s), then continue here.

---

## Step 1 — Developer account verification

Settings → Developer account → Account details

| Field | Value |
|---|---|
| Developer type | Individual |
| Legal name | Zachary Birney |
| Developer name (public) | DazedDingo |
| Email address | zachbirney@gmail.com |
| Phone | (your number — required for SMS verification) |
| Physical address | (per the blocker above) |
| Website | https://dazeddingo.github.io/screendingo/PRIVACY |

Google will email an identity-verification link. Approve it before
trying to create the app.

---

## Step 2 — Create app

All apps → Create app

| Field | Value |
|---|---|
| App name | ScreenDingo |
| Default language | English (United States) — en-US |
| App or game | App |
| Free or paid | Free |
| Declarations: Developer Program Policies | ✓ |
| Declarations: US export laws | ✓ |

---

## Step 3 — Main store listing

Store presence → Main store listing

| Field | Value |
|---|---|
| App name (30) | `ScreenDingo: Couples Movie Picks` |
| Short description (80) | `A shared movie + TV picker for two — learns from both your tastes.` |
| Full description (4000) | (see "Full description" block below — copy verbatim from `LISTING.md`) |

**App icon**: upload `docs/play-store/assets/play-icon-512.png`
(512×512 PNG, alpha channel allowed).

**Feature graphic**: upload `docs/play-store/assets/feature-graphic.png`
(1024×500 PNG, 24-bit RGB — no alpha).

**Phone screenshots** (you still need to capture these): 5 portrait
shots, see `LISTING.md → Screenshots brief` for the recommended set
and captions. Minimum 2; absolute minimum to submit is 2.

**Promo video**: optional. Skip for v1; add later when you have a
30-second screen capture.

---

## Step 4 — Store settings

Store presence → Store settings

| Field | Value |
|---|---|
| App category | Entertainment |
| Tags | Movies & TV · Recommendations · Couples / Partner apps · Watchlist · TV Tracker |
| Store listing contact details — Email | zachbirney@gmail.com |
| Store listing contact details — Phone | (optional, leave blank unless you want public phone support) |
| Store listing contact details — Website | https://dazeddingo.github.io/screendingo/PRIVACY |
| External marketing | Off (you're not driving ad campaigns) |

---

## Step 5 — Privacy policy

Policy → App content → Privacy policy

| Field | Value |
|---|---|
| Privacy policy URL | `https://dazeddingo.github.io/screendingo/PRIVACY` |

(GitHub Pages is live — both `/PRIVACY` and `/PRIVACY.html` return 200.)

---

## Step 6 — App access

Policy → App content → App access

> Does any functionality require login or other restrictions?

**All functionality is available without restrictions.**

Reason: while sign-in is required, the Play reviewer can sign in with
their own Google account and create a one-person household. There's no
gated content behind a paywall, invite code, or non-Google identity
provider. If a reviewer asks for test credentials, send them a fresh
Google account dedicated to Play review with an empty household.

---

## Step 7 — Ads

Policy → App content → Ads

| Question | Answer |
|---|---|
| Does your app contain ads? | **No** |

(No `google_mobile_ads` integration; no AdMob; no third-party ad SDKs.)

---

## Step 8 — Content rating questionnaire (IARC)

Policy → App content → Content rating

Click "Start questionnaire". Email defaults to the developer account
email — fine. Pick **Entertainment / Reference** as the category. Then:

| Question | Answer |
|---|---|
| Violence — references to or depictions of | No |
| Sexual content or nudity | No |
| Strong language | No |
| Controlled substances | No |
| Gambling content | No |
| User-generated content shared with others | **Yes** — your partner sees your ratings and notes |
| User-to-user interaction | **Yes** — pairing with a partner |
| Shares user location | No |
| Allows users to purchase items | No |
| Digital purchases | No |

Expected outcome: **Everyone (PEGI 3 / ESRB Everyone)** across all
regions. If you see PEGI 7 or higher, double-check the violence /
strong-language answers — TMDB-supplied movie titles are NOT a reason
to bump up.

---

## Step 9 — Target audience

Policy → App content → Target audience and content

| Field | Value |
|---|---|
| Target age group | 13+ |
| Appeals to children | No |

Reason for 13+: the app surfaces metadata for adult-rated movies and
TV (which is what users want); Google's policy for "designed for
families" is incompatible with that. 13+ is the lowest age band that
doesn't trigger the COPPA / Designed-for-Families certification work.

---

## Step 10 — Data safety

Policy → App content → Data safety

This is the form Google scrutinises hardest. Pre-drafted answers in
`LISTING.md → Data safety form`. Summary of what to declare:

### Data types collected

- **Personal info → Name** (collected · not shared · not for ads · optional)
- **Personal info → Email address** (collected · not shared · not for ads · required)
- **Personal info → User IDs** (collected · not shared · not for ads · required)
- **App activity → App interactions** (collected · shared with Trakt **if user opts in** · not for ads · required)
- **App activity → In-app search history** (collected · not shared · not for ads · optional)
- **Messages → Other in-app messages** (collected, concierge chat · not shared · not for ads · optional)

Everything else (location, contacts, photos, files, audio, financial
info, health/fitness, web history): **Not collected**.

### Data sharing

Declare these third parties under "Shared with":

| Recipient | Data | Purpose |
|---|---|---|
| Google Firebase | Account info, ratings, watchlist, taste profile, chat history | Backend hosting + AI scoring |
| TMDB | Movie/TV title IDs (no account info) | Metadata lookup |
| Trakt (opt-in) | Ratings + watch history | Two-way sync |
| Google Gemini | Genre tags + seed titles (no account info) | AI recommendations + chat |
| OMDb | IMDb IDs of titles viewed | Critic-score lookup |
| Reddit | Public title queries | Social-proof data |

### Security practices

| Question | Answer |
|---|---|
| Data encrypted in transit | **Yes** |
| Can users request data be deleted | **Yes** — in-app + email request |
| Independent security review | No |
| Committed to Play Families Policy | N/A (not in Families program) |

---

## Step 11 — News / government / financial / health flags

All **No**. ScreenDingo is none of these.

---

## Step 12 — App release setup

Release → Setup → App signing

Play will offer to use Play App Signing — **accept it**. Then upload
your `.aab` (Play will detect the upload key from the AAB metadata).
The Google-managed app signing key SHA-1 will appear under "App signing
key certificate" once the first upload is accepted — **save that
SHA-1**; it goes into Firebase Console as a second fingerprint so
Google Sign-In works for Play-installed users (separate from the
upload-key SHA-1 we already registered).

---

## Step 13 — Internal testing (first release here, NOT Production)

Release → Testing → Internal testing → Create new release

| Field | Value |
|---|---|
| App bundle | Upload `ScreenDingo-v0.12.3.aab` (or whatever version the workflow builds) |
| Release name | (auto-derived from version code) |
| Release notes (en-US) | (paste from `CHANGELOG.md` — top section only, plain English, no commit-style prefixes) |

Add yourself + Mariah as testers under "Testers → Create email list".

After publishing the internal release, Play gives you an **opt-in URL**
— share it with the test list, they install via Play, you verify
everything works end-to-end:

- [ ] Google Sign-In completes (this is where the post-step-12 SHA-1 matters)
- [ ] Trakt OAuth completes
- [ ] FCM push delivers (rate something, partner sees the nudge)
- [ ] Share-to-Save intent fires from another app
- [ ] Concierge chat completes
- [ ] Home widget renders + auto-refreshes

---

## Step 14 — Promote to Production

Release → Production → Create new release → Promote from internal

Same .aab, no rebuild. Production rollout defaults to 100%; consider
phased rollout (20% → 50% → 100%) for the first launch in case of a
field-only crash that didn't surface in Internal.

---

## Full description (paste-ready)

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
issue tracker are public at github.com/DazedDingo/screendingo.
Privacy policy and terms are linked from the Play listing.
```

---

## Asset paths (everything you'll upload)

| Asset | Path | Spec |
|---|---|---|
| Hi-res app icon | `docs/play-store/assets/play-icon-512.png` | 512×512 PNG, ≤1024 KB |
| Feature graphic | `docs/play-store/assets/feature-graphic.png` | 1024×500 PNG (24-bit, no alpha), ≤15 MB |
| Phone screenshots | (to capture from Pixel 8 reference device) | 9:16 portrait, 1080×1920 or larger, 5–8 shots |
| App bundle (.aab) | GitHub Actions artifact from `release-aab.yml` | Signed with upload keystore |

---

## After the first internal release: the second-SHA-1 dance

1. Play Console → Setup → App signing → copy "App signing key certificate" SHA-1.
2. Firebase Console → Project settings → Your apps → `com.household.watchnext` → Add fingerprint → paste it.
3. Download the updated `google-services.json`.
4. Update `GOOGLE_SERVICES_JSON` GitHub secret.
5. Re-run `release-aab.yml` → download new .aab.
6. Upload to Internal testing as a new release.
7. **Now** test Google Sign-In on a Play install — it should work for the first time.

Without this step, Google Sign-In silently fails for Play-installed
users (works fine for sideload because the sideload APK is signed with
your upload key, which Firebase already knows). The Play-delivered APK
is signed with Google's app-signing key, which Firebase doesn't yet know
until you add it as a fingerprint.
