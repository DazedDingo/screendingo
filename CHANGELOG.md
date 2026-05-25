# Changelog

## 0.12.4 (2026-05-25)

- **Play Store pre-launch prep.** Generated Play Console image assets (512×512 hi-res icon + 1024×500 feature graphic with ScreenDingo wordmark) at `docs/play-store/assets/`. Added `docs/play-store/SUBMISSION_GUIDE.md` — paste-ready field-by-field guide for the Play Console submission including all form values, app-signing-key second-fingerprint dance, and the Internal → Production rollout order.
- **Issue-queue abuse mitigations.**
  - **Per-uid daily cap on new batches** (5 / 24h). Implemented in `enqueueIssue` — the rate-limit check runs only when a new batch would be created; appending to an already-pending batch bypasses it (no new GitHub issue is produced). New `RATE_MAX_NEW_BATCHES` / `RATE_WINDOW_MS` exports + `RATE_LIMIT_ERROR` sentinel; the `submitIssue` onCall wrapper translates the sentinel to `HttpsError("resource-exhausted", …)` so clients can render a "Daily report limit reached" snackbar. New Firestore composite index for `(uid, createdAt)` on `issueBatches` so the rate-limit query stays under one Firestore read per submission. Four new Jest tests covering under-cap allow, at-cap throw, append-bypass, and the 24h window constant.
  - **Repo-name fix** in `processIssueQueue.ts` — `REPO_NAME` was still `"watchnext"`, so app-submitted issues were routing via GitHub's 301 redirect to `/screendingo`. The redirect works today but is brittle (and noisy in CF logs). Hardcoded to `"screendingo"`. User-Agent strings in `externalRatings.ts` + `index.ts` (Trakt OAuth) brought along for consistency.
- **Privacy policy postal address** added (UK GDPR Article 13 / Google Play developer-disclosure requirement). Updated `docs/PRIVACY.md` data-controller block.
- **Deployment note**: changes touch Cloud Functions + Firestore indexes. Run `firebase deploy --only functions,firestore:indexes` to land the rate limit + repo-name fix in production. The Play Store assets + privacy update are docs-only and land on the next GitHub Pages rebuild after push (~90s).

## 0.10.0 (2026-04-28)

- Sub-topics filter on Home — new multi-select axis parallel to Genre. Pick "Animal docs" + Genre "Documentary" to surface only wildlife documentaries. AND-intersection both within sub-topics and between Sub-topics + Genre; selecting Sub-topics alone (with an empty Genre selection) narrows the rec pool to titles whose keyword augmentation tagged them with the sub-topic.
- Initial ship list (12 sub-topics from spec, verified against TMDB `/search/keyword` on 2026-04-28):
  - **Animal docs** (wildlife) — TMDB keywords: wildlife (9902), nature (18330), animals (18165), animal (361118), nature documentary (221355), wildlife documentary (324404)
  - **True crime** (true_crime) — true crime (33722)
  - **Music docs** (music_doc) — music documentary (246377), concert film (156205), rockumentary (33899)
  - **History docs** (history_doc) — historical documentary (321490)
  - **Science & tech** (science_tech) — science (287067), technology (1576), space exploration (191132), science documentary (325892)
  - **Sports docs** (sport_doc) — sports documentary (159290)
  - **Slasher horror** (slasher) — slasher (12339)
  - **Cyberpunk** (cyberpunk) — cyberpunk (12190)
  - **Space opera** (space_opera) — space opera (161176)
  - **Found footage** (found_footage) — found footage (163053)
  - **Vampire** (vampire) — vampire (3133)
  - **Zombie** (zombie) — zombie (12377)
- Bonus add-ons (also shipped because their keyword ids were already verified): Kaiju (kaiju, 161791), Heist (heist, 10051), Cosmic horror (cosmic_horror, 215959), Psychological horror (psychological_horror, 295907).
- Sub-topics are populated by the same `/keywords` background fetch the Genre augmenter uses, so cold pools enrich without a manual refresh. `kKeywordsVersion` bumped 2 → 3 so existing rec docs re-fetch keywords once and pick up sub-topic tags on first Home open.
- Sub-topics filter is included in the refresh state hash, so committing a new sub-topic via "Show recommendations" invalidates the dedupe and runs a fresh refresh.
- Sub-topics selection is per-mode-persisted (`wn_subgenres_solo` / `wn_subgenres_together`), same pattern as Genre / media type / awards / sort / curator.
- UI: `_SubGenreSection` sits under the Genre chip row inside the filter panel, default-collapsed so the panel's visual weight is roughly unchanged. Chips render alphabetised by display label.
