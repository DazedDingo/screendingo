import * as logger from "firebase-functions/logger";

/**
 * Real air-time + availability-lag model shared by `notifyNextEpisode.ts`
 * and `refreshUpNextWidget.ts`. See
 * `docs/upnext_airtime_spec.md`-equivalent design note for the full write-up
 * — short version: TMDB's `next_episode_to_air.air_date` is a DATE-ONLY
 * string in the network's local date (usually US), which reads as "today"
 * hours before a UK household could plausibly watch it, and disappears the
 * moment the US date rolls over even if the household hasn't caught up yet.
 * Trakt exposes the real UTC `first_aired` timestamp for free, no auth. We
 * layer a fixed lag on top (torrents/streams land a few hours after airing)
 * and evaluate BOTH `last_episode_to_air` and `next_episode_to_air` so a
 * just-aired episode doesn't vanish before the household can watch it.
 */

const TRAKT_BASE = "https://api.trakt.tv";

/** Fixed availability lag applied server-side (no per-user setting here —
 *  that's a client-only concept). 6h approximates "a few hours after the
 *  US broadcast for a stream/torrent to land". */
export const UPNEXT_LAG_HOURS = 6;

function traktHeaders(clientId: string): Record<string, string> {
  return {
    "trakt-api-version": "2",
    "trakt-api-key": clientId,
    "Content-Type": "application/json",
  };
}

/** `GET /search/tmdb/{tmdbId}?type=show` → the Trakt show id for a TMDB tv
 *  id. Public endpoint, no Authorization header. Never throws — any
 *  non-200 / network error / empty result degrades to `null` so a Trakt
 *  outage never sinks the caller's date-only fallback. */
export async function lookupTraktShowId(
  tmdbId: number,
  clientId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<number | null> {
  try {
    const res = await fetchImpl(
      `${TRAKT_BASE}/search/tmdb/${tmdbId}?type=show`,
      { headers: traktHeaders(clientId) },
    );
    if (!res.ok) return null;
    const json = (await res.json()) as unknown;
    if (!Array.isArray(json)) return null;
    for (const item of json) {
      if (
        item &&
        typeof item === "object" &&
        (item as Record<string, unknown>)["type"] === "show"
      ) {
        const show = (item as Record<string, unknown>)["show"] as
          | Record<string, unknown>
          | undefined;
        const ids = show?.["ids"] as Record<string, unknown> | undefined;
        const traktId = ids?.["trakt"];
        return typeof traktId === "number" ? traktId : null;
      }
    }
    return null;
  } catch (err) {
    logger.warn(`traktAirTime: lookupTraktShowId failed for tmdbId=${tmdbId}`, err);
    return null;
  }
}

/** `GET /shows/{id}/seasons/{s}/episodes/{e}?extended=full` → the episode's
 *  real UTC `first_aired` as a `Date`, or `null` on any failure / missing /
 *  unparseable field. Same no-throw contract as `lookupTraktShowId`. */
export async function fetchEpisodeFirstAired(
  traktShowId: number,
  season: number,
  number: number,
  clientId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Date | null> {
  try {
    const res = await fetchImpl(
      `${TRAKT_BASE}/shows/${traktShowId}/seasons/${season}/episodes/${number}?extended=full`,
      { headers: traktHeaders(clientId) },
    );
    if (!res.ok) return null;
    const json = (await res.json()) as Record<string, unknown>;
    const firstAired = json["first_aired"];
    if (typeof firstAired !== "string" || firstAired.length === 0) return null;
    const d = new Date(firstAired);
    if (Number.isNaN(d.getTime())) return null;
    return d;
  } catch (err) {
    logger.warn(
      `traktAirTime: fetchEpisodeFirstAired failed for traktShowId=${traktShowId} s${season}e${number}`,
      err,
    );
    return null;
  }
}

export interface TraktIdCache {
  /** Resolves + memoizes the tmdbId→traktId lookup so a batch of N
   *  candidates for the same show only ever calls Trakt's search endpoint
   *  once per invocation (the mapping never changes). */
  get(
    tmdbId: number,
    clientId: string,
    fetchImpl?: typeof fetch,
  ): Promise<number | null>;
}

/** Simple per-invocation cache — construct one per scheduled-function run
 *  and share it across every household/show it processes. */
export function createTraktIdCache(): TraktIdCache {
  const cache = new Map<number, number | null>();
  return {
    async get(tmdbId, clientId, fetchImpl = fetch) {
      if (cache.has(tmdbId)) return cache.get(tmdbId) as number | null;
      const id = await lookupTraktShowId(tmdbId, clientId, fetchImpl);
      cache.set(tmdbId, id);
      return id;
    },
  };
}

export type Availability = {
  availableAt: Date;
  /** Calendar-day difference (UTC) between `now` and `availableAt`. 0 =
   *  available today. */
  daysUntil: number;
  /** True when `availableAt` carries a real time-of-day (resolved via
   *  Trakt); false when it's the date-only midnight fallback. */
  hasTime: boolean;
};

/** UTC-midnight timestamp for a Date, used to diff calendar days regardless
 *  of time-of-day. */
function utcMidnightMs(d: Date): number {
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

/** Pure: steps 2–3 of the availability model, all in UTC.
 *  - `airsAtUtc` present → `availableAt = airsAtUtc + lagHours` (hasTime=true).
 *  - else → fallback to `airDate` at UTC midnight, no lag (hasTime=false),
 *    matching the pre-Trakt date-only behaviour.
 *  - `daysUntil` is a UTC calendar-day diff between `now` and `availableAt`.
 *  Returns `null` when there's nothing to go on (`airDate` missing /
 *  unparseable AND `airsAtUtc` is null). */
export function computeAvailability({
  airDate,
  airsAtUtc,
  lagHours,
  now,
}: {
  airDate: string | null | undefined;
  airsAtUtc: Date | null;
  lagHours: number;
  now: Date;
}): Availability | null {
  let availableAt: Date;
  let hasTime: boolean;
  if (airsAtUtc) {
    availableAt = new Date(airsAtUtc.getTime() + lagHours * 60 * 60 * 1000);
    hasTime = true;
  } else {
    if (!airDate) return null;
    const ms = Date.parse(`${airDate}T00:00:00Z`);
    if (Number.isNaN(ms)) return null;
    availableAt = new Date(ms);
    hasTime = false;
  }
  const daysUntil = Math.round(
    (utcMidnightMs(availableAt) - utcMidnightMs(now)) / 86400000,
  );
  return { availableAt, daysUntil, hasTime };
}

export type EpisodeCandidate = {
  season: number;
  number: number;
  name: string | null;
  airDate: string | null;
};

/** Pure: builds the [last, next] candidate list from a TMDB `/tv/{id}`
 *  payload, dropping nulls and deduping by (season, number) — `last` and
 *  `next` are occasionally the same episode (TMDB hasn't rolled over yet). */
export function candidateEpisodes(
  showJson: Record<string, unknown> | null | undefined,
): EpisodeCandidate[] {
  if (!showJson) return [];
  const out: EpisodeCandidate[] = [];
  const seen = new Set<string>();
  for (const key of ["last_episode_to_air", "next_episode_to_air"]) {
    const ep = showJson[key] as Record<string, unknown> | null | undefined;
    if (!ep) continue;
    const season = ep["season_number"];
    const number = ep["episode_number"];
    if (typeof season !== "number" || typeof number !== "number") continue;
    const dedupeKey = `${season}:${number}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    out.push({
      season,
      number,
      name: (ep["name"] as string | null | undefined) ?? null,
      airDate: (ep["air_date"] as string | null | undefined) ?? null,
    });
  }
  return out;
}

export type ResolvedAvailability = {
  candidate: EpisodeCandidate;
  availability: Availability;
};

/** Pure-ish (network access is fully delegated to the caller-supplied
 *  resolver): implements spec step 4 — evaluate every candidate, resolve
 *  its real air time via `resolveAirsAtUtc`, drop candidates outside
 *  `[-windowBehindDays, +windowAheadDays]`, and keep the one with the
 *  EARLIEST `availableAt`. Shared by both scheduled functions:
 *  `refreshUpNextWidget.ts` passes its 7-day-ahead/1-day-behind window;
 *  `notifyNextEpisode.ts` passes `0/0` to mean "only a candidate becoming
 *  available exactly today qualifies". Injecting the resolver (rather than
 *  hardcoding a Trakt call) is what makes this testable without any
 *  network or Firestore mocking — tests pass a stub resolver. */
export async function pickBestAvailability(
  candidates: EpisodeCandidate[],
  resolveAirsAtUtc: (candidate: EpisodeCandidate) => Promise<Date | null>,
  opts: {
    lagHours: number;
    now: Date;
    windowAheadDays: number;
    windowBehindDays: number;
  },
): Promise<ResolvedAvailability | null> {
  let best: ResolvedAvailability | null = null;
  for (const candidate of candidates) {
    const airsAtUtc = await resolveAirsAtUtc(candidate);
    const availability = computeAvailability({
      airDate: candidate.airDate,
      airsAtUtc,
      lagHours: opts.lagHours,
      now: opts.now,
    });
    if (!availability) continue;
    if (
      availability.daysUntil < -opts.windowBehindDays ||
      availability.daysUntil > opts.windowAheadDays
    ) {
      continue;
    }
    if (!best || availability.availableAt.getTime() < best.availability.availableAt.getTime()) {
      best = { candidate, availability };
    }
  }
  return best;
}

/** HH:mm zero-padded, UTC — server has no household timezone so it uses
 *  UTC for both the clock and "now"; the client recomputes in local time
 *  on next open. */
function formatUtcHHmm(d: Date): string {
  const hh = d.getUTCHours().toString().padStart(2, "0");
  const mm = d.getUTCMinutes().toString().padStart(2, "0");
  return `${hh}:${mm}`;
}

/** Pure: relative-time label. Mirrors the client's label rules 1:1 (see
 *  spec "Labels" section) — identical output to the pre-Trakt
 *  `relativeWhenLabel(daysUntil)` when `hasTime` is false/omitted, so every
 *  existing call site + test keeps working untouched. */
export function relativeWhenLabel(
  daysUntil: number,
  opts?: { hasTime?: boolean; availableAt?: Date; now?: Date },
): string {
  const hasTime = opts?.hasTime ?? false;
  if (daysUntil === 0) {
    if (hasTime && opts?.availableAt && opts?.now) {
      if (opts.now.getTime() >= opts.availableAt.getTime()) return "Out now";
      return `Today ~${formatUtcHHmm(opts.availableAt)}`;
    }
    return "Out today";
  }
  if (daysUntil === 1) {
    if (hasTime && opts?.availableAt) {
      return `Tomorrow ~${formatUtcHHmm(opts.availableAt)}`;
    }
    return "Tomorrow";
  }
  if (daysUntil === -1) return "Aired yesterday";
  if (daysUntil < -1) return "Just aired";
  return `In ${daysUntil}d`;
}
