import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  candidateEpisodes,
  createTraktIdCache,
  EpisodeCandidate,
  fetchEpisodeFirstAired,
  pickBestAvailability,
  relativeWhenLabel,
  UPNEXT_LAG_HOURS,
  TraktIdCache,
} from "./traktAirTime";

// Re-exported so existing imports (`import { relativeWhenLabel } from
// "./refreshUpNextWidget"`) keep working now that the label formatter lives
// in the shared `traktAirTime.ts` module alongside the availability model.
export { relativeWhenLabel } from "./traktAirTime";

// Mirrors `lib/providers/upnext_provider.dart` — same window, same cap so
// the FCM-pushed payload looks identical to what the in-app row would render
// if the user opened the app right now.
export const REFRESH_WIDGET_MAX_TILES = 3;
export const REFRESH_WIDGET_WINDOW_DAYS_AHEAD = 7;
export const REFRESH_WIDGET_WINDOW_DAYS_BEHIND = 1;

const TMDB_API_KEY = defineSecret("TMDB_API_KEY");
// Trakt is used to resolve each candidate episode's real UTC air time (see
// `traktAirTime.ts`); the client id is not a secret in principle (it's sent
// as a request header on public endpoints) but is already managed as one
// via the existing `TRAKT_CLIENT_ID` secret declared in `index.ts` for the
// OAuth callables — redeclaring it here (same pattern as `OMDB_API_KEY` in
// `externalRatings.ts`) avoids a circular import from index.ts.
const TRAKT_CLIENT_ID = defineSecret("TRAKT_CLIENT_ID");

export type NextEp = {
  airDate: string;
  seasonNumber: number;
  episodeNumber: number;
  episodeName?: string | null;
};

export type UpNextRow = {
  tmdbId: number;
  showTitle: string;
  posterPath?: string | null;
  next: NextEp;
  /** Days from `today` (UTC) to `availableAt` (see `traktAirTime.ts`).
   *  Negative = became available N days ago. 0 = available today. */
  daysUntil: number;
  /** When the episode is expected to actually be available to watch —
   *  Trakt `first_aired` + lag when resolved, else `next.airDate` at UTC
   *  midnight. Drives both the final sort and the relative-time label. */
  availableAt: Date;
  /** True when `availableAt` carries a real Trakt-resolved time-of-day. */
  hasTime: boolean;
};

/** YYYY-MM-DD (UTC). Matches the daily notifyNextEpisode scheduler frame. */
export function todayUtcIso(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/** Pure: days between two YYYY-MM-DD strings, anchored to UTC midnight. */
export function daysBetweenUtc(a: string, b: string): number {
  const da = Date.parse(`${a}T00:00:00Z`);
  const db = Date.parse(`${b}T00:00:00Z`);
  if (Number.isNaN(da) || Number.isNaN(db)) return 0;
  return Math.round((db - da) / 86400000);
}

/** Pure: matches `_episodeLabel` in `home_widget_service.dart`. */
export function episodeLabel(
  season: number,
  episode: number,
  name: string | null | undefined,
): string {
  const s = `S${season}E${episode}`;
  const trimmed = (name ?? "").trim();
  return trimmed.length === 0 ? s : `${s} · ${trimmed}`;
}

/** Pure: matches `_episodeUri` in `home_widget_service.dart`. */
export function episodeUri(
  tmdbId: number,
  season: number,
  episode: number,
): string {
  return `wn://title/tv/${tmdbId}?season=${season}&episode=${episode}`;
}

/** Pure: pick the rows whose `daysUntil` lands in the in-app window
 *  (today - WINDOW_BEHIND to today + WINDOW_AHEAD) and stable-sort by
 *  soonest availability (ties broken by exact `availableAt`). Mirrors the
 *  client's `upNextProvider` selection so the widget never disagrees with
 *  what the app would show. */
export function pickUpNextRows(
  today: string,
  rows: UpNextRow[],
  {
    maxTiles = REFRESH_WIDGET_MAX_TILES,
    windowAhead = REFRESH_WIDGET_WINDOW_DAYS_AHEAD,
    windowBehind = REFRESH_WIDGET_WINDOW_DAYS_BEHIND,
  }: {
    maxTiles?: number;
    windowAhead?: number;
    windowBehind?: number;
  } = {},
): UpNextRow[] {
  const inWindow = rows.filter((r) => {
    const d = r.daysUntil;
    return d >= -windowBehind && d <= windowAhead;
  });
  inWindow.sort(
    (a, b) =>
      a.daysUntil - b.daysUntil ||
      a.availableAt.getTime() - b.availableAt.getTime(),
  );
  return inWindow.slice(0, maxTiles);
}

export type SourceEntry = {
  tmdbId: number;
  title: string;
  posterPath: string | null;
  inProgressStatus: string | null;
  /** True when any member's `watched_by` flag is set. */
  watchedByAny: boolean;
};

export type SourceWatchlistRow = {
  tmdbId: number;
  title: string;
  posterPath: string | null;
};

export type UpNextSourceShow = {
  tmdbId: number;
  title: string;
  posterPath: string | null;
};

/** Pure: merge the two Up Next sources — TV watch entries + shared-scope
 *  TV watchlist rows — into a deduped show list. Mirrors the client's
 *  `upNextEligibleTvIds` in `lib/providers/upnext_provider.dart`:
 *  entries with `in_progress_status == 'watching'` are always in;
 *  watchlist rows join unless the household is already done with the
 *  show (entry completed/dropped, or watched by any member). Solo-scope
 *  watchlist rows never reach this function — the payload is pushed to
 *  every member, so only shared rows are queried (same privacy contract
 *  as the Stremio catalog). */
export function collectUpNextShows(
  entries: SourceEntry[],
  watchlist: SourceWatchlistRow[],
): UpNextSourceShow[] {
  const out: UpNextSourceShow[] = [];
  const seen = new Set<number>();
  const finished = new Set<number>();
  for (const e of entries) {
    if (e.inProgressStatus === "watching") {
      if (!seen.has(e.tmdbId)) {
        seen.add(e.tmdbId);
        out.push({ tmdbId: e.tmdbId, title: e.title, posterPath: e.posterPath });
      }
    } else if (
      e.inProgressStatus === "completed" ||
      e.inProgressStatus === "dropped" ||
      e.watchedByAny
    ) {
      finished.add(e.tmdbId);
    }
  }
  for (const w of watchlist) {
    if (seen.has(w.tmdbId) || finished.has(w.tmdbId)) continue;
    seen.add(w.tmdbId);
    out.push({ tmdbId: w.tmdbId, title: w.title, posterPath: w.posterPath });
  }
  return out;
}

/** Build the FCM `data` map for a refresh push. Keys mirror the
 *  SharedPreferences slot names the AppWidgetProvider reads
 *  (`up_next_${i}_*` + `up_next_count`), so the background handler can
 *  copy them across without parsing. All values are strings — FCM data
 *  maps don't carry typed values. `now` drives the "Out now" vs
 *  "Today ~HH:mm" branch of the label and defaults to the real clock. */
export function buildFcmDataPayload(
  rows: UpNextRow[],
  now: Date = new Date(),
): Record<string, string> {
  const out: Record<string, string> = {
    type: "refresh_widget",
    up_next_count: rows.length.toString(),
  };
  for (let i = 0; i < REFRESH_WIDGET_MAX_TILES; i++) {
    if (i < rows.length) {
      const r = rows[i];
      out[`up_next_${i}_title`] = r.showTitle;
      out[`up_next_${i}_episode_label`] = episodeLabel(
        r.next.seasonNumber,
        r.next.episodeNumber,
        r.next.episodeName,
      );
      out[`up_next_${i}_when`] = relativeWhenLabel(r.daysUntil, {
        hasTime: r.hasTime,
        availableAt: r.availableAt,
        now,
      });
      out[`up_next_${i}_uri`] = episodeUri(
        r.tmdbId,
        r.next.seasonNumber,
        r.next.episodeNumber,
      );
    } else {
      // Sentinel so the bg handler can clear stale slots — FCM doesn't
      // forward keys-with-null, so we encode "absent" as an empty string.
      out[`up_next_${i}_title`] = "";
      out[`up_next_${i}_episode_label`] = "";
      out[`up_next_${i}_when`] = "";
      out[`up_next_${i}_uri`] = "";
    }
  }
  return out;
}

// ─── Orchestration (integration territory, not unit-tested) ─────────────────

async function fetchShowEpisodesPayload(
  tmdbId: number,
  apiKey: string,
): Promise<Record<string, unknown> | null> {
  // Same lean `/tv/{id}` call as before, but we now read BOTH
  // `last_episode_to_air` and `next_episode_to_air` (via `candidateEpisodes`)
  // instead of just the next one — see traktAirTime.ts model doc. Trim
  // defends against `\n` in Secret Manager values (gotcha 35b).
  const url = `https://api.themoviedb.org/3/tv/${tmdbId}?api_key=${apiKey.trim()}&language=en-US`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return (await res.json()) as Record<string, unknown>;
  } catch (err) {
    logger.warn(`refreshUpNextWidget: TMDB lookup failed for tmdbId=${tmdbId}`, err);
    return null;
  }
}

/** Resolves a single show's Up Next row: fetch TMDB candidates, resolve
 *  each candidate's real air time via Trakt (skipped entirely when
 *  `clientId` is empty — falls back to date-only), compute availability,
 *  drop out-of-window candidates, and keep the earliest-available one.
 *  Returns `null` when the show has no episode in-window (or the TMDB
 *  lookup itself failed) — a single show's Trakt/TMDB failure never
 *  aborts the batch. */
async function resolveShowRow(
  show: UpNextSourceShow,
  apiKey: string,
  clientId: string,
  idCache: TraktIdCache,
  now: Date,
): Promise<UpNextRow | null> {
  const showJson = await fetchShowEpisodesPayload(show.tmdbId, apiKey);
  const candidates = candidateEpisodes(showJson);
  if (candidates.length === 0) return null;

  const resolveAirsAtUtc = async (candidate: EpisodeCandidate): Promise<Date | null> => {
    if (!clientId) return null;
    try {
      const traktShowId = await idCache.get(show.tmdbId, clientId);
      if (traktShowId == null) return null;
      return await fetchEpisodeFirstAired(
        traktShowId,
        candidate.season,
        candidate.number,
        clientId,
      );
    } catch (err) {
      // Defensive — the Trakt helpers already swallow their own errors,
      // but a show's Trakt failure must never abort the batch.
      logger.warn(`refreshUpNextWidget: Trakt lookup failed for tmdbId=${show.tmdbId}`, err);
      return null;
    }
  };

  const best = await pickBestAvailability(candidates, resolveAirsAtUtc, {
    lagHours: UPNEXT_LAG_HOURS,
    now,
    windowAheadDays: REFRESH_WIDGET_WINDOW_DAYS_AHEAD,
    windowBehindDays: REFRESH_WIDGET_WINDOW_DAYS_BEHIND,
  });
  if (!best) return null;

  return {
    tmdbId: show.tmdbId,
    showTitle: show.title,
    posterPath: show.posterPath,
    next: {
      airDate: best.candidate.airDate ?? "",
      seasonNumber: best.candidate.season,
      episodeNumber: best.candidate.number,
      episodeName: best.candidate.name,
    },
    daysUntil: best.availability.daysUntil,
    availableAt: best.availability.availableAt,
    hasTime: best.availability.hasTime,
  };
}

async function refreshHousehold(
  db: admin.firestore.Firestore,
  hhId: string,
  apiKey: string,
  clientId: string,
  idCache: TraktIdCache,
  today: string,
  now: Date,
): Promise<{ pushed: number; errors: number }> {
  // 1. All TV entries (not just watching — completed/dropped/watched
  //    state is needed to exclude finished shows the watchlist still
  //    carries) + shared-scope TV watchlist rows.
  const entriesSnap = await db
    .collection(`households/${hhId}/watchEntries`)
    .where("media_type", "==", "tv")
    .get();
  const watchlistSnap = await db
    .collection(`households/${hhId}/watchlist`)
    .where("media_type", "==", "tv")
    .where("scope", "==", "shared")
    .get();

  const entries: SourceEntry[] = [];
  for (const doc of entriesSnap.docs) {
    const data = doc.data();
    const tmdbId = data["tmdb_id"] as number | undefined;
    const title = data["title"] as string | undefined;
    if (!tmdbId || !title) continue;
    const watchedBy =
      (data["watched_by"] as Record<string, boolean> | undefined) ?? {};
    entries.push({
      tmdbId,
      title,
      posterPath: (data["poster_path"] as string | null | undefined) ?? null,
      inProgressStatus:
        (data["in_progress_status"] as string | null | undefined) ?? null,
      watchedByAny: Object.values(watchedBy).some((v) => v === true),
    });
  }
  const watchlistRows: SourceWatchlistRow[] = [];
  for (const doc of watchlistSnap.docs) {
    const data = doc.data();
    const tmdbId = data["tmdb_id"] as number | undefined;
    const title = data["title"] as string | undefined;
    if (!tmdbId || !title) continue;
    watchlistRows.push({
      tmdbId,
      title,
      posterPath: (data["poster_path"] as string | null | undefined) ?? null,
    });
  }

  const shows = collectUpNextShows(entries, watchlistRows);
  if (shows.length === 0) return { pushed: 0, errors: 0 };

  const rows: UpNextRow[] = [];
  for (const show of shows) {
    try {
      const row = await resolveShowRow(show, apiKey, clientId, idCache, now);
      if (row) rows.push(row);
    } catch (err) {
      // A single show's failure must never abort the batch.
      logger.warn(`refreshUpNextWidget: row resolution failed for tmdbId=${show.tmdbId}`, err);
    }
  }

  const picked = pickUpNextRows(today, rows);
  // We still send when picked is empty so the widget clears stale tiles.
  const payload = buildFcmDataPayload(picked, now);

  const membersSnap = await db.collection(`households/${hhId}/members`).get();
  const tokens: string[] = [];
  for (const m of membersSnap.docs) {
    const t = m.data()["fcm_token"] as string | undefined;
    if (t) tokens.push(t);
  }
  if (tokens.length === 0) return { pushed: 0, errors: 0 };

  let pushed = 0;
  let errors = 0;
  for (const token of tokens) {
    try {
      await admin.messaging().send({
        token,
        data: payload,
        // data-only — no `notification` field. The bg handler runs silently
        // and updates the widget without surfacing a tray notification.
        android: { priority: "high" },
      });
      pushed++;
    } catch (err) {
      errors++;
      logger.warn(`refreshUpNextWidget: FCM failed hh=${hhId}`, err);
    }
  }
  return { pushed, errors };
}

/**
 * Every 6h, push a silent FCM data message to every household member with
 * the latest Up Next payload. The client's background message handler
 * writes the flat keys straight into home_widget SharedPreferences and
 * triggers an AppWidget update — no app launch required, no Riverpod /
 * Firestore work in the background isolate.
 *
 * Cadence rationale: 6h is fine-grained enough that the relative-time
 * label ("Tomorrow", "In 3d") stays accurate even at timezone edges, and
 * coarse enough to stay well under FCM and CF free-tier budgets (4
 * invocations/day × ~2 tokens per household × tiny payload = effectively
 * zero cost).
 */
export const refreshUpNextWidgetEvery6Hours = onSchedule(
  {
    schedule: "0 */6 * * *",
    timeZone: "Etc/UTC",
    region: "europe-west2",
    secrets: [TMDB_API_KEY, TRAKT_CLIENT_ID],
  },
  async () => {
    const apiKey = TMDB_API_KEY.value();
    if (!apiKey) {
      logger.error("refreshUpNextWidget: TMDB_API_KEY secret unset; skipping");
      return;
    }
    // Empty is a valid runtime state (secret not yet set for this project) —
    // resolveShowRow treats an empty clientId as "skip Trakt, use the
    // date-only fallback", same as a Trakt outage would.
    const clientId = TRAKT_CLIENT_ID.value() ?? "";
    const now = new Date();
    const today = todayUtcIso(now);
    const idCache = createTraktIdCache();
    const db = admin.firestore();
    const hhSnap = await db.collection("households").get();
    let totalPushed = 0;
    let totalErrors = 0;
    for (const hh of hhSnap.docs) {
      const { pushed, errors } = await refreshHousehold(
        db,
        hh.id,
        apiKey,
        clientId,
        idCache,
        today,
        now,
      );
      totalPushed += pushed;
      totalErrors += errors;
    }
    logger.info(
      `refreshUpNextWidget: pushed=${totalPushed} errors=${totalErrors}`,
    );
  },
);
