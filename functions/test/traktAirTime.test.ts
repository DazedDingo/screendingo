import {
  candidateEpisodes,
  computeAvailability,
  createTraktIdCache,
  fetchEpisodeFirstAired,
  lookupTraktShowId,
  relativeWhenLabel,
  UPNEXT_LAG_HOURS,
} from "../src/traktAirTime";

function fakeResponse(overrides: {
  ok?: boolean;
  status?: number;
  json?: unknown;
} = {}): Response {
  const { ok = true, status = 200, json = {} } = overrides;
  return {
    ok,
    status,
    json: async () => json,
  } as unknown as Response;
}

describe("lookupTraktShowId", () => {
  test("happy path: hits the right URL + headers (no Authorization), returns show.ids.trakt", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({
        json: [
          { type: "movie", movie: { ids: { trakt: 999 } } },
          { type: "show", show: { ids: { trakt: 1390 } } },
        ],
      }),
    );

    const id = await lookupTraktShowId(1399, "client-id-abc", fetchImpl);

    expect(id).toBe(1390);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, opts] = fetchImpl.mock.calls[0];
    expect(url).toBe("https://api.trakt.tv/search/tmdb/1399?type=show");
    expect(opts.headers).toEqual({
      "trakt-api-version": "2",
      "trakt-api-key": "client-id-abc",
      "Content-Type": "application/json",
    });
    expect(opts.headers["Authorization"]).toBeUndefined();
  });

  test("non-200 response returns null", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({ ok: false, status: 404 }));
    expect(await lookupTraktShowId(1, "k", fetchImpl)).toBeNull();
  });

  test("empty array returns null", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({ json: [] }));
    expect(await lookupTraktShowId(1, "k", fetchImpl)).toBeNull();
  });

  test("array with no show-typed entries returns null", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({ json: [{ type: "movie", movie: { ids: { trakt: 1 } } }] }),
    );
    expect(await lookupTraktShowId(1, "k", fetchImpl)).toBeNull();
  });

  test("fetch throws → null", async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error("network down"));
    expect(await lookupTraktShowId(1, "k", fetchImpl)).toBeNull();
  });
});

describe("fetchEpisodeFirstAired", () => {
  test("happy path: hits the right URL + headers (no Authorization), returns Date", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({ json: { first_aired: "2026-05-15T02:00:00.000Z" } }),
    );

    const d = await fetchEpisodeFirstAired(1390, 3, 4, "client-id-abc", fetchImpl);

    expect(d).toEqual(new Date("2026-05-15T02:00:00.000Z"));
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, opts] = fetchImpl.mock.calls[0];
    expect(url).toBe(
      "https://api.trakt.tv/shows/1390/seasons/3/episodes/4?extended=full",
    );
    expect(opts.headers).toEqual({
      "trakt-api-version": "2",
      "trakt-api-key": "client-id-abc",
      "Content-Type": "application/json",
    });
    expect(opts.headers["Authorization"]).toBeUndefined();
  });

  test("non-200 response returns null", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({ ok: false, status: 404 }));
    expect(await fetchEpisodeFirstAired(1, 1, 1, "k", fetchImpl)).toBeNull();
  });

  test("first_aired: null returns null", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({ json: { first_aired: null } }));
    expect(await fetchEpisodeFirstAired(1, 1, 1, "k", fetchImpl)).toBeNull();
  });

  test("unparseable first_aired returns null", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({ json: { first_aired: "not-a-date" } }),
    );
    expect(await fetchEpisodeFirstAired(1, 1, 1, "k", fetchImpl)).toBeNull();
  });

  test("fetch throws → null", async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error("boom"));
    expect(await fetchEpisodeFirstAired(1, 1, 1, "k", fetchImpl)).toBeNull();
  });
});

describe("createTraktIdCache", () => {
  test("looks up a tmdbId only once across repeated .get() calls", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({ json: [{ type: "show", show: { ids: { trakt: 42 } } }] }),
    );
    const cache = createTraktIdCache();

    const a = await cache.get(1399, "k", fetchImpl);
    const b = await cache.get(1399, "k", fetchImpl);

    expect(a).toBe(42);
    expect(b).toBe(42);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  test("caches a null result too (doesn't retry a show trakt can't find)", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({ json: [] }));
    const cache = createTraktIdCache();

    await cache.get(7, "k", fetchImpl);
    await cache.get(7, "k", fetchImpl);

    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  test("distinct tmdbIds each get their own lookup", async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({ json: [{ type: "show", show: { ids: { trakt: 1 } } }] }),
    );
    const cache = createTraktIdCache();

    await cache.get(1, "k", fetchImpl);
    await cache.get(2, "k", fetchImpl);

    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});

describe("computeAvailability", () => {
  const now = new Date("2026-05-15T10:00:00.000Z");

  test("with airsAtUtc + lag: availableAt is shifted, hasTime true", () => {
    const airsAtUtc = new Date("2026-05-16T02:00:00.000Z"); // tomorrow 02:00 UTC
    const result = computeAvailability({
      airDate: "2026-05-15",
      airsAtUtc,
      lagHours: UPNEXT_LAG_HOURS,
      now,
    });

    expect(result).not.toBeNull();
    expect(result!.hasTime).toBe(true);
    expect(result!.availableAt).toEqual(new Date("2026-05-16T08:00:00.000Z"));
    expect(result!.daysUntil).toBe(1);
  });

  test("airsAtUtc same UTC day as now → daysUntil 0", () => {
    const airsAtUtc = new Date("2026-05-15T02:00:00.000Z");
    const result = computeAvailability({
      airDate: "2026-05-15",
      airsAtUtc,
      lagHours: 6,
      now,
    });
    expect(result!.daysUntil).toBe(0);
    expect(result!.hasTime).toBe(true);
  });

  test("fallback to date-only midnight when airsAtUtc is null", () => {
    const result = computeAvailability({
      airDate: "2026-05-15",
      airsAtUtc: null,
      lagHours: UPNEXT_LAG_HOURS,
      now,
    });
    expect(result).not.toBeNull();
    expect(result!.hasTime).toBe(false);
    expect(result!.availableAt).toEqual(new Date("2026-05-15T00:00:00.000Z"));
    expect(result!.daysUntil).toBe(0);
  });

  test("missing airDate and null airsAtUtc → null", () => {
    expect(
      computeAvailability({ airDate: null, airsAtUtc: null, lagHours: 6, now }),
    ).toBeNull();
    expect(
      computeAvailability({ airDate: undefined, airsAtUtc: null, lagHours: 6, now }),
    ).toBeNull();
  });

  test("unparseable airDate and null airsAtUtc → null", () => {
    expect(
      computeAvailability({ airDate: "not-a-date", airsAtUtc: null, lagHours: 6, now }),
    ).toBeNull();
  });
});

describe("candidateEpisodes", () => {
  test("returns both last and next when present and distinct", () => {
    const out = candidateEpisodes({
      last_episode_to_air: {
        season_number: 1,
        episode_number: 5,
        name: "Last",
        air_date: "2026-05-08",
      },
      next_episode_to_air: {
        season_number: 1,
        episode_number: 6,
        name: "Next",
        air_date: "2026-05-15",
      },
    });
    expect(out).toEqual([
      { season: 1, number: 5, name: "Last", airDate: "2026-05-08" },
      { season: 1, number: 6, name: "Next", airDate: "2026-05-15" },
    ]);
  });

  test("dedupes when last and next are the same episode", () => {
    const ep = {
      season_number: 2,
      episode_number: 1,
      name: "Premiere",
      air_date: "2026-05-15",
    };
    const out = candidateEpisodes({ last_episode_to_air: ep, next_episode_to_air: ep });
    expect(out).toHaveLength(1);
  });

  test("drops null candidates", () => {
    const out = candidateEpisodes({
      last_episode_to_air: null,
      next_episode_to_air: {
        season_number: 1,
        episode_number: 1,
        name: null,
        air_date: null,
      },
    });
    expect(out).toEqual([{ season: 1, number: 1, name: null, airDate: null }]);
  });

  test("both null → empty array", () => {
    expect(
      candidateEpisodes({ last_episode_to_air: null, next_episode_to_air: null }),
    ).toEqual([]);
  });

  test("missing season/episode number drops the candidate", () => {
    const out = candidateEpisodes({
      last_episode_to_air: { season_number: null, episode_number: 1, name: "x", air_date: "d" },
    });
    expect(out).toEqual([]);
  });

  test("null/undefined showJson returns empty array", () => {
    expect(candidateEpisodes(null)).toEqual([]);
    expect(candidateEpisodes(undefined)).toEqual([]);
  });
});

describe("relativeWhenLabel", () => {
  test("d=0, no opts (date-only) → Out today — matches old behaviour", () => {
    expect(relativeWhenLabel(0)).toBe("Out today");
  });

  test("d=0, hasTime, now before availableAt → Today ~HH:mm", () => {
    const availableAt = new Date("2026-05-15T14:30:00.000Z");
    const now = new Date("2026-05-15T09:00:00.000Z");
    expect(relativeWhenLabel(0, { hasTime: true, availableAt, now })).toBe(
      "Today ~14:30",
    );
  });

  test("d=0, hasTime, now at/after availableAt → Out now", () => {
    const availableAt = new Date("2026-05-15T08:00:00.000Z");
    const now = new Date("2026-05-15T09:00:00.000Z");
    expect(relativeWhenLabel(0, { hasTime: true, availableAt, now })).toBe("Out now");
  });

  test("d=1, no opts → Tomorrow — matches old behaviour", () => {
    expect(relativeWhenLabel(1)).toBe("Tomorrow");
  });

  test("d=1, hasTime → Tomorrow ~HH:mm", () => {
    const availableAt = new Date("2026-05-16T08:00:00.000Z");
    expect(relativeWhenLabel(1, { hasTime: true, availableAt })).toBe(
      "Tomorrow ~08:00",
    );
  });

  test("d=-1 → Aired yesterday", () => {
    expect(relativeWhenLabel(-1)).toBe("Aired yesterday");
  });

  test("d<-1 → Just aired", () => {
    expect(relativeWhenLabel(-3)).toBe("Just aired");
  });

  test("d>1 → In Nd", () => {
    expect(relativeWhenLabel(4)).toBe("In 4d");
  });
});
