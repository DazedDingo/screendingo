# Preliminary trademark search — 2026-05-24

**Scope**: Pre-launch clearance check for the names "WatchNext" and
"DazedDingo" ahead of commercial Play Store distribution. Searches
covered: USPTO via Trademarkia (blocked, indirect-only), EUIPO eSearch
(JS-rendered, indirect-only), web/app-store presence, common-law use
evidence. Both Trademarkia and EUIPO's direct search endpoints are JS-
gated and returned no machine-readable data; conclusions below rely on
indirect search engine indexing plus app-store live listings.

**Not legal advice.** This is a preliminary check to flag obvious
conflicts. Before paying for a Play Console listing under any name,
hire an actual trademark attorney for a $200-$500 USPTO + EUIPO + UK
IPO clearance opinion. Money-on-the-line decisions need a professional
sign-off — what's below is a "is it worth even talking to an attorney"
filter.

---

## "WatchNext" — DO NOT use as the commercial brand

Three concurrent commercial uses identified, all in the
exact-overlap "movie/TV recommender + watchlist mobile app"
category that WatchNext sits in:

### 1. Google's "Watch Next" (Android TV system feature)

Google operates the "Watch Next" content row on Android TV / Google TV
as a first-party platform feature, documented at
[developer.android.com/training/tv/discovery/watch-next-add-programs](https://developer.android.com/training/tv/discovery/watch-next-add-programs).
Whether Google has registered this as a trademark in IC 9 / IC 41 isn't
confirmable from the public USPTO search via my tooling, but Google's
*use in commerce* of "Watch Next" as a product name for an
entertainment-software feature is unambiguous and well-documented.

**Risk**: Google has a history of aggressively defending trademark-class
overlap, especially for entertainment-software product names. A new
"WatchNext" app on Play Store (Google's own distribution channel) is
the maximally-visible place to attract their attention.

### 2. "Watch Next: AI Movie Finder" by Filippe Frulli

Live on Google Play (`com.filippefrulli.watch_next`) and iOS App Store
(`id6450368827`). Munich-based developer (filippefrulli.dev@gmail.com).

**Direct feature overlap with our app**:
- AI-powered streaming recommendations ✓ (same)
- Personal watchlist ✓ (same)
- TV episode tracker ✓ (same)
- Cross-platform availability lookup ✓ (we don't do this)
- AI chat ("ask for vibes") ✓ (same as our concierge)

**Their differentiation**: Personal-use only, no couples/household
sharing.

**Risk**: This is the strongest common-law trademark conflict. Same
name, same category, same channel (Play Store), same Android-developer
ecosystem. Even without federal registration, Filippe Frulli has 2+
years of continuous commercial use to establish a common-law mark in
the EU + US. Listing under the same name would be likely-to-confuse
under both [US Lanham Act §43(a)](https://www.law.cornell.edu/uscode/text/15/1125)
and [EU Trade Mark Regulation Art 9](https://eur-lex.europa.eu/eli/reg/2017/1001/oj)
*regardless of registration status*.

### 3. "WatchNext" by Sagar Mahobia (iOS App Store, id1560814890)

Single-word exact match. Described as "comprehensive movie and TV show
discovery app that allows you to explore a wide range of popular and
trending content." Featured set overlap unknown (App Store page
returned 404 during this check — possibly pulled from active sale, but
the entry still appears in search indexes).

**Risk**: Lower than #1/#2 if the app is delisted, but the trademark
status (if filed at USPTO) would persist after the listing is pulled.
Confirm with USPTO search before assuming clean.

### Additional noise — direct app-store competitors in adjacent space

These don't use "WatchNext" but compete on the couples-recommendation
pitch and signal that the market is crowded:
- [Matched: Movie App For Couples](https://apps.apple.com/us/app/matched-movie-app-for-couples/id1623287922)
- [MatchaFilm](https://matchafilm.app/)
- [MovieSwipe – AI Movie Finder](https://apps.apple.com/us/app/movieswipe-ai-movie-finder/id6740416271)
- [Couplesy](https://play.google.com/store/apps/details?id=com.minu.lovehub)
- Wever, Minu, Watch2Gether

---

## "DazedDingo" — clean as a brand identity

Zero trademark hits across the indirect searches. Closest matches were
unrelated prefixes ("DAZZ", "DAZITE", "DAZYDABS"). No app-store
products under this name. Safe to use as the developer-display name on
Play Console and as your @-handle on GitHub.

**Caveat**: this confirms only that no obvious conflicts are indexed by
search engines. For a definitive answer, USPTO TESS direct search +
EUIPO eSearch + UK IPO are all free public databases worth 5 minutes of
your time each.

---

## Recommendation

**Pick a new commercial brand name.** "WatchNext" is too crowded for a
paid Play Store listing. Three options:

### Option A — Lead with "DazedDingo" as a product line

Examples:
- `DazedDingo: Movie Match` — pairs your brand with the couples USP
- `Pair Pick by DazedDingo` — names the workflow not the category
- `DazedDingo Watchlist` — generic but cleanly yours

**Pro**: You already have DazedDingo trademark-clean. New name is
automatically derivative-clean.
**Con**: "DazedDingo" is unfamiliar; user won't associate it with what
the app does until they read the description.

### Option B — A unique evocative name in the same neighbourhood

Brainstormed options that ride the couples + recommendation theme:
- `PairPick` / `Pair & Pick`
- `TwoPlay`
- `WatchWith` / `WatchWith Us`
- `OurNext`
- `BetweenUs Movies`
- `CouchPair`
- `DuoPick`
- `BothPick`
- `WeWatch`
- `MovieMatch` (likely taken — check)
- `TasteSync`

**Pro**: Memorable, on-brand for "watching with someone".
**Con**: Every word will need its own trademark search before you
commit. Budget 1-2 hours per candidate.

### Option C — Rebrand to a non-overlapping niche

Lean into what makes this different from the generic recommendation
apps:
- `Couplet` (already a publishing brand — likely taken)
- `Tandem Tonight`
- `Two-Up`
- `JoinTheQueue`
- `Compromise.tv`
- `BothAgree`

**Pro**: Maximum naming-conflict freedom.
**Con**: Larger marketing/asset rework.

---

## Pre-launch verification checklist (do these before committing to a name)

1. **USPTO Trademark Search** ([tmsearch.uspto.gov](https://tmsearch.uspto.gov))
   - Direct text search for the candidate name
   - Filter to LIVE registrations + applications
   - Check Class 9 (downloadable software), Class 41 (entertainment
     services), Class 42 (SaaS)
2. **EUIPO eSearch** ([euipo.europa.eu/eSearch](https://euipo.europa.eu/eSearch))
   - Same filters; covers all 27 EU member states
3. **UK IPO Search** ([trademarks.ipo.gov.uk](https://trademarks.ipo.gov.uk))
   - Required since you're UK-resident; EUIPO no longer covers UK
4. **App Store live-search check** — Play Store + iOS App Store search
   for the name
5. **Domain availability** — `.com` and `.app` at minimum
6. **Google search** — quoted name + "app" + "trademark"

If all six come back clean → commission a paid attorney opinion (~$300)
for formal clearance before printing letterhead.

---

## What to do with the existing "WatchNext" code

The name change is a Play-listing-and-marketing concern, not a
codebase concern. You can keep the repo, Firestore project, and
`com.household.watchnext` package ID — none of those are
user-facing. The user-facing rebrand touches:

- App display name (`android/app/src/main/AndroidManifest.xml`)
- App icon wordmark (`WatchNextLogo` widget — repaint with new name)
- Splash screen
- Profile → About footer
- README + LICENSE + PRIVACY + TERMS (regex-replace "WatchNext" with
  new brand)
- All Play Console listing copy (`docs/play-store/LISTING.md`)

Maybe 2-3 hours of plumbing per name swap. Worth doing once on the
final chosen name rather than iterating on a placeholder.
