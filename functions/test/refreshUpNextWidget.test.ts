import {
  buildFcmDataPayload,
  collectUpNextShows,
  SourceEntry,
  SourceWatchlistRow,
  daysBetweenUtc,
  episodeLabel,
  episodeUri,
  pickUpNextRows,
  relativeWhenLabel,
  REFRESH_WIDGET_MAX_TILES,
  REFRESH_WIDGET_WINDOW_DAYS_AHEAD,
  REFRESH_WIDGET_WINDOW_DAYS_BEHIND,
  UpNextRow,
} from "../src/refreshUpNextWidget";
import {
  candidateEpisodes,
  pickBestAvailability,
  UPNEXT_LAG_HOURS,
} from "../src/traktAirTime";

// Arbitrary fixed anchor so `daysUntil`-only tests (hasTime=false) don't
// need to care about the exact clock — only the day-diff from `daysUntil`
// matters for those assertions.
const ARBITRARY_ANCHOR_MS = Date.UTC(2026, 0, 1);

function row(o: Partial<UpNextRow> & { daysUntil: number }): UpNextRow {
  return {
    tmdbId: o.tmdbId ?? 1,
    showTitle: o.showTitle ?? "Show",
    posterPath: o.posterPath ?? "/p.jpg",
    next: o.next ?? {
      airDate: "2026-05-16",
      seasonNumber: 1,
      episodeNumber: 1,
      episodeName: "Pilot",
    },
    daysUntil: o.daysUntil,
    hasTime: o.hasTime ?? false,
    availableAt: o.availableAt ?? new Date(ARBITRARY_ANCHOR_MS + o.daysUntil * 86400000),
  };
}

describe("daysBetweenUtc", () => {
  test("returns 0 for same date", () => {
    expect(daysBetweenUtc("2026-05-15", "2026-05-15")).toBe(0);
  });
  test("returns positive for future", () => {
    expect(daysBetweenUtc("2026-05-15", "2026-05-18")).toBe(3);
  });
  test("returns negative for past", () => {
    expect(daysBetweenUtc("2026-05-15", "2026-05-13")).toBe(-2);
  });
  test("crosses month boundary correctly", () => {
    expect(daysBetweenUtc("2026-04-30", "2026-05-02")).toBe(2);
  });
  test("malformed input returns 0 rather than NaN", () => {
    expect(daysBetweenUtc("garbage", "2026-05-15")).toBe(0);
  });
});

describe("relativeWhenLabel", () => {
  test("today / tomorrow / yesterday short forms", () => {
    expect(relativeWhenLabel(0)).toBe("Out today");
    expect(relativeWhenLabel(1)).toBe("Tomorrow");
    expect(relativeWhenLabel(-1)).toBe("Aired yesterday");
  });
  test("more-than-yesterday-past collapses to Just aired", () => {
    expect(relativeWhenLabel(-3)).toBe("Just aired");
  });
  test("future > 1 day uses In Nd", () => {
    expect(relativeWhenLabel(4)).toBe("In 4d");
  });
});

describe("episodeLabel", () => {
  test("with episode name", () => {
    expect(episodeLabel(3, 4, "Big Reveal")).toBe("S3E4 · Big Reveal");
  });
  test("trims whitespace-only names to code only", () => {
    expect(episodeLabel(3, 4, "   ")).toBe("S3E4");
  });
  test("null/undefined name yields code only", () => {
    expect(episodeLabel(1, 1, null)).toBe("S1E1");
    expect(episodeLabel(1, 1, undefined)).toBe("S1E1");
  });
});

describe("episodeUri", () => {
  test("encodes season + episode into wn:// path query", () => {
    expect(episodeUri(1399, 3, 4)).toBe("wn://title/tv/1399?season=3&episode=4");
  });
});

describe("pickUpNextRows", () => {
  const today = "2026-05-15";
  test("returns sorted-by-soonest within the window", () => {
    const out = pickUpNextRows(today, [
      row({ tmdbId: 1, daysUntil: 3 }),
      row({ tmdbId: 2, daysUntil: 0 }),
      row({ tmdbId: 3, daysUntil: 1 }),
    ]);
    expect(out.map((r) => r.tmdbId)).toEqual([2, 3, 1]);
  });
  test("drops items beyond the window-ahead bound", () => {
    const out = pickUpNextRows(today, [
      row({ tmdbId: 1, daysUntil: REFRESH_WIDGET_WINDOW_DAYS_AHEAD }),
      row({ tmdbId: 2, daysUntil: REFRESH_WIDGET_WINDOW_DAYS_AHEAD + 1 }),
    ]);
    expect(out.map((r) => r.tmdbId)).toEqual([1]);
  });
  test("drops items further-back than the window-behind bound", () => {
    const out = pickUpNextRows(today, [
      row({ tmdbId: 1, daysUntil: -REFRESH_WIDGET_WINDOW_DAYS_BEHIND }),
      row({ tmdbId: 2, daysUntil: -REFRESH_WIDGET_WINDOW_DAYS_BEHIND - 1 }),
    ]);
    expect(out.map((r) => r.tmdbId)).toEqual([1]);
  });
  test("caps at MAX_TILES (default 3)", () => {
    const out = pickUpNextRows(today, [
      row({ tmdbId: 1, daysUntil: 0 }),
      row({ tmdbId: 2, daysUntil: 1 }),
      row({ tmdbId: 3, daysUntil: 2 }),
      row({ tmdbId: 4, daysUntil: 3 }),
      row({ tmdbId: 5, daysUntil: 4 }),
    ]);
    expect(out).toHaveLength(REFRESH_WIDGET_MAX_TILES);
    expect(out.map((r) => r.tmdbId)).toEqual([1, 2, 3]);
  });
  test("empty input returns empty", () => {
    expect(pickUpNextRows(today, [])).toEqual([]);
  });
});

describe("buildFcmDataPayload", () => {
  test("encodes count, slots, and clears unused slots with empty strings", () => {
    const out = buildFcmDataPayload([
      row({
        tmdbId: 1399,
        showTitle: "GoT",
        daysUntil: 0,
        next: {
          airDate: "2026-05-15",
          seasonNumber: 3,
          episodeNumber: 4,
          episodeName: "Big Reveal",
        },
      }),
    ]);
    expect(out["type"]).toBe("refresh_widget");
    expect(out["up_next_count"]).toBe("1");
    expect(out["up_next_0_title"]).toBe("GoT");
    expect(out["up_next_0_episode_label"]).toBe("S3E4 · Big Reveal");
    expect(out["up_next_0_when"]).toBe("Out today");
    expect(out["up_next_0_uri"]).toBe("wn://title/tv/1399?season=3&episode=4");
    // Unused slots must be present (so bg handler can clear stale prefs) and
    // empty (FCM data maps don't allow null).
    for (let i = 1; i < REFRESH_WIDGET_MAX_TILES; i++) {
      expect(out[`up_next_${i}_title`]).toBe("");
      expect(out[`up_next_${i}_episode_label`]).toBe("");
      expect(out[`up_next_${i}_when`]).toBe("");
      expect(out[`up_next_${i}_uri`]).toBe("");
    }
  });
  test("empty rows → count=0, every slot blank, type still set", () => {
    const out = buildFcmDataPayload([]);
    expect(out["type"]).toBe("refresh_widget");
    expect(out["up_next_count"]).toBe("0");
    for (let i = 0; i < REFRESH_WIDGET_MAX_TILES; i++) {
      expect(out[`up_next_${i}_title`]).toBe("");
    }
  });
  test("every value is a string (FCM data map contract)", () => {
    const out = buildFcmDataPayload([row({ daysUntil: 1 })]);
    for (const v of Object.values(out)) {
      expect(typeof v).toBe("string");
    }
  });
});

describe("collectUpNextShows", () => {
  const entry = (
    tmdbId: number,
    o: Partial<SourceEntry> = {},
  ): SourceEntry => ({
    tmdbId,
    title: o.title ?? `Show ${tmdbId}`,
    posterPath: o.posterPath ?? null,
    inProgressStatus: o.inProgressStatus ?? null,
    watchedByAny: o.watchedByAny ?? false,
  });
  const saved = (tmdbId: number): SourceWatchlistRow => ({
    tmdbId,
    title: `Saved ${tmdbId}`,
    posterPath: null,
  });

  test("watching entries always included", () => {
    const out = collectUpNextShows(
      [entry(1, { inProgressStatus: "watching" })],
      [],
    );
    expect(out.map((s) => s.tmdbId)).toEqual([1]);
  });

  test("watchlist rows join the pool", () => {
    const out = collectUpNextShows([], [saved(2), saved(3)]);
    expect(out.map((s) => s.tmdbId)).toEqual([2, 3]);
  });

  test("show in both sources dedupes to the entry (title from entry)", () => {
    const out = collectUpNextShows(
      [entry(4, { inProgressStatus: "watching", title: "Entry Title" })],
      [saved(4)],
    );
    expect(out).toHaveLength(1);
    expect(out[0].title).toBe("Entry Title");
  });

  test("completed/dropped/watched entries veto their watchlist row", () => {
    const out = collectUpNextShows(
      [
        entry(5, { inProgressStatus: "completed" }),
        entry(6, { inProgressStatus: "dropped" }),
        entry(7, { watchedByAny: true }),
        entry(8),
      ],
      [saved(5), saved(6), saved(7), saved(8)],
    );
    expect(out.map((s) => s.tmdbId)).toEqual([8]);
  });

  test("empty both sides returns empty", () => {
    expect(collectUpNextShows([], [])).toEqual([]);
  });
});

// ─── Trakt-air-time pipeline (spec: real air time + availability lag) ──────
//
// `resolveShowRow` (private orchestration in refreshUpNextWidget.ts) wires
// TMDB fetch + Trakt id-cache + `candidateEpisodes` + `pickBestAvailability`
// together; these tests exercise that exact composition using the widget's
// own window constants (7 days ahead / 1 day behind), with a stubbed
// `resolveAirsAtUtc` in place of a real Trakt HTTP call — so the whole
// per-show candidate → availability → label pipeline is covered without any
// network or Firestore mocking.
describe("Trakt-air-time pipeline (widget window)", () => {
  const now = new Date("2026-05-15T09:00:00.000Z");

  function widgetWindow() {
    return {
      lagHours: UPNEXT_LAG_HOURS,
      now,
      windowAheadDays: REFRESH_WIDGET_WINDOW_DAYS_AHEAD,
      windowBehindDays: REFRESH_WIDGET_WINDOW_DAYS_BEHIND,
    };
  }

  test("Trakt path changes the label: date-only 'Out today' becomes 'Tomorrow ~08:00' once the real air time is resolved", async () => {
    const showJson = {
      last_episode_to_air: null,
      next_episode_to_air: {
        season_number: 3,
        episode_number: 4,
        name: "Big Reveal",
        air_date: "2026-05-15", // TMDB says "today" (US date)
      },
    };
    const candidates = candidateEpisodes(showJson);

    // Date-only fallback (no Trakt) — old behaviour.
    const dateOnly = await pickBestAvailability(
      candidates,
      async () => null,
      widgetWindow(),
    );
    expect(dateOnly!.availability.hasTime).toBe(false);
    expect(relativeWhenLabel(dateOnly!.availability.daysUntil)).toBe("Out today");

    // Trakt resolves the real air time to 02:00 UTC the *next* day; +6h lag
    // pushes availability to 08:00 UTC tomorrow.
    const withTrakt = await pickBestAvailability(
      candidates,
      async () => new Date("2026-05-16T02:00:00.000Z"),
      widgetWindow(),
    );
    expect(withTrakt!.availability.hasTime).toBe(true);
    expect(withTrakt!.availability.daysUntil).toBe(1);
    expect(
      relativeWhenLabel(withTrakt!.availability.daysUntil, {
        hasTime: withTrakt!.availability.hasTime,
        availableAt: withTrakt!.availability.availableAt,
        now,
      }),
    ).toBe("Tomorrow ~08:00");
  });

  test("last_episode_to_air available today beats next_episode_to_air in 7 days", async () => {
    const showJson = {
      last_episode_to_air: {
        season_number: 2,
        episode_number: 9,
        name: "Finale",
        air_date: "2026-05-15", // today
      },
      next_episode_to_air: {
        season_number: 3,
        episode_number: 1,
        name: "Premiere",
        air_date: "2026-05-22", // 7 days out
      },
    };
    const candidates = candidateEpisodes(showJson);

    const best = await pickBestAvailability(candidates, async () => null, widgetWindow());

    expect(best!.candidate.number).toBe(9);
    expect(best!.candidate.season).toBe(2);
    expect(best!.availability.daysUntil).toBe(0);
  });

  test("Trakt lookup failing (404-equivalent → resolver returns null) degrades to the old date-only behaviour", async () => {
    const showJson = {
      last_episode_to_air: null,
      next_episode_to_air: {
        season_number: 1,
        episode_number: 1,
        name: "Pilot",
        air_date: "2026-05-16", // tomorrow
      },
    };
    const candidates = candidateEpisodes(showJson);

    const best = await pickBestAvailability(candidates, async () => null, widgetWindow());

    expect(best).not.toBeNull();
    expect(best!.availability.hasTime).toBe(false);
    // Matches the pre-Trakt daysBetweenUtc("2026-05-15", "2026-05-16") == 1.
    expect(best!.availability.daysUntil).toBe(
      daysBetweenUtc("2026-05-15", "2026-05-16"),
    );
    expect(relativeWhenLabel(best!.availability.daysUntil)).toBe("Tomorrow");
  });

  test("candidate outside the window is dropped even when Trakt resolves a time", async () => {
    const showJson = {
      last_episode_to_air: null,
      next_episode_to_air: {
        season_number: 1,
        episode_number: 1,
        name: null,
        air_date: "2026-06-01", // far beyond the 7-day-ahead window
      },
    };
    const candidates = candidateEpisodes(showJson);

    const best = await pickBestAvailability(
      candidates,
      async () => new Date("2026-06-01T02:00:00.000Z"),
      widgetWindow(),
    );

    expect(best).toBeNull();
  });
});
