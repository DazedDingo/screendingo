#!/usr/bin/env python3
"""
Resolves TMDB keyword names → ids for lib/utils/keyword_genre_augment.dart's
`kKeywordToSubgenres` map, and emits a matching `kSubgenreParents` map
declaring which canonical genres each sub-topic is a child of.

Sub-topics are contextual: a sub-topic is shown in the Home filter panel
ONLY when at least one of its parent genres is in the user's selected
Genre set (or when it's already selected). Picking "Animal docs" without
Documentary selected is incoherent — Animal docs is a *narrowing* of
Documentary, not a parallel filter.

Run:

    TMDB_API_KEY=... python3 scripts/generate_keyword_subgenre_map.py

Each seed below is (tag, label, [parent_genre_names], [keyword_query_names]).
Multiple keyword queries per tag is the OR-union pattern — every keyword
that reliably implies the tag widens the pool. Parent genre names must
match utils/tmdb_genres.dart exactly (Movie set is canonical; the runtime
genreMatches() pulls in TV synonyms via kGenreSynonyms).
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

# (tag, label, [parent_genre_names], [keyword_query_names])
SEEDS: list[tuple[str, str, list[str], list[str]]] = [
    # ── Documentary children ────────────────────────────────────────────
    ("wildlife", "Animal docs", ["Documentary"],
     ["wildlife", "nature", "animals", "animal", "nature documentary", "wildlife documentary"]),
    ("true_crime", "True crime", ["Documentary", "Crime"],
     ["true crime"]),
    ("music_doc", "Music docs", ["Documentary", "Music"],
     ["music documentary", "concert film", "rockumentary"]),
    ("history_doc", "History docs", ["Documentary", "History"],
     ["historical documentary"]),
    ("science_tech", "Science & tech", ["Documentary"],
     ["science", "technology", "space exploration", "science documentary"]),
    ("sport_doc", "Sports docs", ["Documentary"],
     ["sports documentary"]),
    ("food_doc", "Food & cooking", ["Documentary"],
     ["food", "cooking", "chef", "culinary"]),
    ("travel_doc", "Travel docs", ["Documentary"],
     ["travel"]),
    ("political_doc", "Political docs", ["Documentary"],
     ["politics", "political"]),
    ("environmental_doc", "Climate & nature", ["Documentary"],
     ["climate change", "environment", "environmentalism"]),

    # ── Horror children ─────────────────────────────────────────────────
    ("slasher", "Slasher", ["Horror"], ["slasher"]),
    ("found_footage", "Found footage", ["Horror"], ["found footage"]),
    ("psychological_horror", "Psychological horror", ["Horror"], ["psychological horror"]),
    ("cosmic_horror", "Cosmic horror", ["Horror"], ["cosmic horror"]),
    ("vampire", "Vampire", ["Horror"], ["vampire"]),
    ("zombie", "Zombie", ["Horror"], ["zombie"]),
    ("body_horror", "Body horror", ["Horror"], ["body horror"]),
    ("supernatural", "Supernatural", ["Horror"], ["supernatural"]),
    ("gothic", "Gothic", ["Horror"], ["gothic"]),
    ("monster", "Monster", ["Horror"], ["monster"]),
    ("demonic", "Demonic / possession", ["Horror"], ["exorcism", "demonic possession"]),
    ("witchcraft", "Witchcraft / occult", ["Horror"], ["witch", "witchcraft", "occult"]),

    # ── Sci-Fi children ─────────────────────────────────────────────────
    ("cyberpunk", "Cyberpunk", ["Science Fiction"], ["cyberpunk"]),
    ("space_opera", "Space opera", ["Science Fiction"], ["space opera"]),
    ("kaiju", "Kaiju", ["Science Fiction"], ["kaiju"]),
    ("time_travel", "Time travel", ["Science Fiction"], ["time travel"]),
    ("dystopia", "Dystopia", ["Science Fiction"], ["dystopia"]),
    ("post_apocalyptic", "Post-apocalyptic", ["Science Fiction"], ["post-apocalyptic future"]),
    ("alien_invasion", "Alien invasion", ["Science Fiction"], ["alien invasion"]),
    ("artificial_intelligence", "AI / robots", ["Science Fiction"], ["artificial intelligence", "robot"]),
    ("virtual_reality", "Virtual reality", ["Science Fiction"], ["virtual reality"]),

    # ── Crime children (the heavily-requested fill) ────────────────────
    ("heist", "Heist", ["Crime"], ["heist"]),
    ("mafia", "Mafia / mob", ["Crime"], ["mafia", "mob"]),
    ("detective", "Detective / noir", ["Crime", "Mystery"], ["detective", "private detective", "neo-noir"]),
    ("gangster", "Gangster", ["Crime"], ["gangster"]),
    ("drug_trade", "Drug trade / cartel", ["Crime"], ["drug cartel", "drug trafficking"]),
    ("prison", "Prison", ["Crime"], ["prison"]),
    ("serial_killer", "Serial killer", ["Crime", "Thriller"], ["serial killer"]),
    ("undercover", "Undercover", ["Crime"], ["undercover"]),
    ("hitman", "Hitman / assassin", ["Crime", "Action"], ["hitman", "assassin"]),

    # ── Action children ─────────────────────────────────────────────────
    ("martial_arts", "Martial arts", ["Action"], ["martial arts", "kung fu"]),
    ("spy", "Spy / espionage", ["Action", "Thriller"], ["spy", "espionage"]),
    ("military", "Military", ["Action", "War"], ["military"]),
    ("superhero", "Superhero", ["Action"], ["superhero"]),

    # ── Comedy children ─────────────────────────────────────────────────
    ("dark_comedy", "Dark comedy", ["Comedy"], ["dark comedy", "black comedy"]),
    ("romcom", "Romantic comedy", ["Comedy", "Romance"], ["romantic comedy"]),
    ("satire", "Satire", ["Comedy"], ["satire"]),
    ("mockumentary", "Mockumentary", ["Comedy"], ["mockumentary"]),
    ("slapstick", "Slapstick", ["Comedy"], ["slapstick"]),

    # ── Drama children ──────────────────────────────────────────────────
    ("courtroom", "Courtroom / legal", ["Drama"], ["courtroom drama", "courtroom"]),
    ("coming_of_age", "Coming of age", ["Drama"], ["coming of age"]),
    ("period_drama", "Period drama", ["Drama"], ["period drama"]),
    ("biopic", "Biopic", ["Drama"], ["biography", "biopic"]),

    # ── Fantasy children ────────────────────────────────────────────────
    ("high_fantasy", "High fantasy", ["Fantasy"], ["high fantasy"]),
    ("dark_fantasy", "Dark fantasy", ["Fantasy"], ["dark fantasy"]),
    ("fairy_tale", "Fairy tale", ["Fantasy", "Family"], ["fairy tale"]),

    # ── Thriller children ───────────────────────────────────────────────
    ("psychological_thriller", "Psychological thriller", ["Thriller"], ["psychological thriller"]),
    ("political_thriller", "Political thriller", ["Thriller"], ["political thriller"]),
    ("conspiracy", "Conspiracy", ["Thriller"], ["conspiracy"]),

    # ── Western children ────────────────────────────────────────────────
    ("neo_western", "Neo-western", ["Western"], ["neo-western"]),
    ("spaghetti_western", "Spaghetti western", ["Western"], ["spaghetti western"]),

    # ── War children ────────────────────────────────────────────────────
    ("wwii", "WWII", ["War"], ["world war ii", "ww2"]),
    ("vietnam_war", "Vietnam war", ["War"], ["vietnam war"]),

    # ── Mystery children ────────────────────────────────────────────────
    ("whodunit", "Whodunit", ["Mystery"], ["whodunit"]),

    # ── Adventure children ──────────────────────────────────────────────
    ("treasure_hunt", "Treasure hunt", ["Adventure"], ["treasure hunt"]),
    ("exploration", "Exploration", ["Adventure"], ["exploration"]),

    # ── Music children ──────────────────────────────────────────────────
    ("musical", "Musical", ["Music"], ["musical"]),

    # ── Animation children ──────────────────────────────────────────────
    ("anime", "Anime", ["Animation"], ["anime"]),
    ("stop_motion", "Stop motion", ["Animation"], ["stop motion"]),

    # ── History children ────────────────────────────────────────────────
    ("ancient_history", "Ancient history", ["History"], ["ancient rome", "ancient greece", "ancient egypt"]),
    ("medieval", "Medieval", ["History"], ["medieval"]),
]

TMDB_BASE = "https://api.themoviedb.org/3"


def search_keyword(name: str, api_key: str) -> list[dict]:
    url = (
        f"{TMDB_BASE}/search/keyword?"
        f"api_key={api_key}&query={urllib.parse.quote(name)}"
    )
    with urllib.request.urlopen(url, timeout=15) as res:
        return json.load(res).get("results", [])


def pick_exact(name: str, results: list[dict]) -> dict | None:
    """Strict exact-match only — sub-genre seeds must be unambiguous; a
    fuzzy fallback risks tagging titles with the wrong concept."""
    if not results:
        return None
    lowered = name.lower()
    for r in results:
        if r.get("name", "").lower() == lowered:
            return r
    return None


def main() -> int:
    api_key = os.environ.get("TMDB_API_KEY")
    if not api_key:
        print("error: set TMDB_API_KEY", file=sys.stderr)
        return 2

    keyword_to_subgenres: dict[int, set[str]] = {}
    subgenre_labels: dict[str, str] = {}
    subgenre_parents: dict[str, list[str]] = {}
    misses: list[tuple[str, str]] = []

    for tag, label, parents, queries in SEEDS:
        subgenre_labels[tag] = label
        subgenre_parents[tag] = parents
        for q in queries:
            try:
                results = search_keyword(q, api_key)
            except Exception as e:
                print(f"// ERROR fetching {q!r}: {e}", file=sys.stderr)
                misses.append((tag, q))
                continue
            match = pick_exact(q, results)
            if match is None:
                misses.append((tag, q))
                continue
            kid = match["id"]
            keyword_to_subgenres.setdefault(kid, set()).add(tag)
            time.sleep(0.04)

    # Emit the keyword→subgenres map, grouped by tag for readability.
    print("// ─── Generated by scripts/generate_keyword_subgenre_map.py ───")
    print("// Paste into lib/utils/keyword_genre_augment.dart#kKeywordToSubgenres.")
    print()
    print("const Map<int, Set<String>> kKeywordToSubgenres = <int, Set<String>>{")
    by_tag: dict[str, list[tuple[int, str]]] = {}
    for kid, tags in keyword_to_subgenres.items():
        for t in tags:
            by_tag.setdefault(t, []).append((kid, t))
    for tag, _, _, _ in SEEDS:
        entries = by_tag.get(tag, [])
        if not entries:
            continue
        print(f"  // ── {tag} ({subgenre_labels[tag]}) ──")
        for kid, _t in sorted(entries):
            tagset = ", ".join(f"'{x}'" for x in sorted(keyword_to_subgenres[kid]))
            print(f"  {kid}: {{{tagset}}},")
    print("};")
    print()

    # Emit the subgenre→parents map.
    print("// Paste into lib/utils/keyword_genre_augment.dart#kSubgenreParents.")
    print("const Map<String, Set<String>> kSubgenreParents = <String, Set<String>>{")
    for tag, label, parents, _ in SEEDS:
        if tag not in by_tag:
            continue  # all queries missed; skip
        parent_set = ", ".join(f"'{p}'" for p in parents)
        print(f"  '{tag}': {{{parent_set}}}, // {label}")
    print("};")
    print()

    # Emit subgenreLabel switch arms.
    print("// Replace lib/utils/keyword_genre_augment.dart#subgenreLabel arms with:")
    for tag, label, _, _ in SEEDS:
        if tag not in by_tag:
            continue
        print(f"      '{tag}' => '{label}',")
    print()

    if misses:
        print("", file=sys.stderr)
        print(f"// {len(misses)} keyword(s) unresolved:", file=sys.stderr)
        for tag, q in misses:
            print(f"//   {tag}: no exact match for {q!r}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
