# Changelog

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
