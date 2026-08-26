import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import {
  candidateEpisodes,
  createTraktIdCache,
  EpisodeCandidate,
  fetchEpisodeFirstAired,
  pickBestAvailability,
  TraktIdCache,
  UPNEXT_LAG_HOURS,
} from "./traktAirTime";

/**
 * Daily push notification: "next episode of an in-progress show is
 * available today".
 *
 * Reuses the data shape behind the client-side `upNextProvider`. For each
 * household, scan watch entries with `media_type='tv'` AND
 * `in_progress_status='watching'`, evaluate both `last_episode_to_air` and
 * `next_episode_to_air` (TMDB `/tv/{id}`) through the shared
 * Trakt-air-time + lag model in `traktAirTime.ts`, and if the resulting
 * `availableAt` lands on today (UTC calendar day — `daysUntil === 0`), send
 * one FCM push per household member token.
 *
 * Idempotency: every successful push stamps
 * `last_episode_notified_for: '{YYYY-MM-DD}'` on the watch entry. The
 * helper short-circuits when the stamp matches the resolved availability
 * date already, so a repeat cron invocation in the same day is a no-op.
 * Once the next episode rolls over to a new availability date, the stamp
 * is stale and the push fires again on that day.
 *
 * Cost: 1 cron/day × ~few households × ~1 TMDB call per in-progress
 * show (+1 Trakt search + 1 Trakt episode call per candidate, cached per
 * show for the id lookup). Free-tier safe — TMDB is unmetered, Trakt is a
 * free public endpoint, FCM is free, the CF runs once a day.
 */

const TMDB_API_KEY = defineSecret("TMDB_API_KEY");
// See refreshUpNextWidget.ts for why this is redeclared here rather than
// imported from index.ts (mirrors the externalRatings.ts OMDB_API_KEY
// pattern — avoids a circular import).
const TRAKT_CLIENT_ID = defineSecret("TRAKT_CLIENT_ID");

/** Pure helper. Decides which watch entries need a push, given today's
 *  date, the in-progress watch entries, and the per-tmdbId resolved
 *  availability info. Excluded:
 *    - shows with no episode becoming available today (cancelled, airs on
 *      a different day, etc)
 *    - shows already notified for the same availability date (idempotency)
 *  Test target — orchestration around it (Firestore, TMDB, Trakt, FCM) is
 *  integration territory and skipped from unit tests. */
export type WatchEntryRow = {
  entryId: string;
  tmdbId: number;
  title: string;
  posterPath?: string | null;
  /** Already-stamped availability date from a prior successful notify, or
   *  undefined if never notified. */
  lastEpisodeNotifiedFor?: string;
};

export type NextEpisodeInfo = {
  /** Effective availability date (YYYY-MM-DD, UTC) — Trakt-air-time +
   *  lag adjusted when resolved, else TMDB's raw `air_date`. Always equal
   *  to `today` by construction (the orchestration layer only produces a
   *  non-null result when the episode becomes available today). */
  airDate: string;
  seasonNumber: number;
  episodeNumber: number;
  episodeName?: string | null;
  /** True when `availableAt` carries a real Trakt-resolved time-of-day
   *  rather than the date-only midnight fallback. Optional — omitted by
   *  older callers/tests, in which case message wording falls back to the
   *  date-only phrasing. */
  hasTime?: boolean;
  /** The resolved availability instant, used only for "is out now" vs
   *  "is out today" message wording. */
  availableAt?: Date;
};

export type Notification = {
  entryId: string;
  tmdbId: number;
  showTitle: string;
  posterPath?: string | null;
  airDate: string;
  seasonNumber: number;
  episodeNumber: number;
  episodeName?: string | null;
  hasTime?: boolean;
  availableAt?: Date;
};

export function pickEntriesNeedingNotify(
  today: string,
  entries: WatchEntryRow[],
  nextEpByTmdbId: Record<number, NextEpisodeInfo | null>,
): Notification[] {
  const out: Notification[] = [];
  for (const entry of entries) {
    const next = nextEpByTmdbId[entry.tmdbId];
    if (!next) continue;
    if (next.airDate !== today) continue;
    if (entry.lastEpisodeNotifiedFor === next.airDate) continue;
    out.push({
      entryId: entry.entryId,
      tmdbId: entry.tmdbId,
      showTitle: entry.title,
      posterPath: entry.posterPath ?? null,
      airDate: next.airDate,
      seasonNumber: next.seasonNumber,
      episodeNumber: next.episodeNumber,
      episodeName: next.episodeName ?? null,
      hasTime: next.hasTime,
      availableAt: next.availableAt,
    });
  }
  return out;
}

/** Format `S##E##` for push body. Pure. */
export function formatEpisodeLabel(season: number, episode: number): string {
  const s = season.toString().padStart(2, "0");
  const e = episode.toString().padStart(2, "0");
  return `S${s}E${e}`;
}

/** Pure: push notification title, wording kept consistent with the
 *  relative-time label semantics used elsewhere — a Trakt-resolved time
 *  that has already passed reads as "is out now"; everything else
 *  (date-only fallback, or a Trakt time later today) reads as "is out
 *  today" (announcing that today is the day, even before the precise
 *  availability instant arrives). */
export function formatNotifyTitle(
  hasTime: boolean | undefined,
  availableAt: Date | undefined,
  now: Date,
): string {
  const outNow =
    hasTime === true && availableAt != null && now.getTime() >= availableAt.getTime();
  return outNow ? "New episode is out now" : "New episode out today";
}

/** Today as YYYY-MM-DD in Etc/UTC. The CF schedule uses UTC; matching the
 *  scheduler's reference frame avoids "off by one" edge cases at midnight
 *  in the household's local zone. */
function todayUtcIso(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

async function fetchShowEpisodesPayload(
  tmdbId: number,
  apiKey: string,
): Promise<Record<string, unknown> | null> {
  // Lean /tv/{id} call — same endpoint the client `upNextProvider` uses,
  // returns both `last_episode_to_air` and `next_episode_to_air` in the
  // base payload. Trim defends against trailing newlines in Secret
  // Manager values (same class of bug that bit OMDb in gotcha 35b — `\n`
  // URL-encodes to `%0A` and the upstream rejects the request as "Invalid
  // API key").
  const url = `https://api.themoviedb.org/3/tv/${tmdbId}?api_key=${apiKey.trim()}&language=en-US`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return (await res.json()) as Record<string, unknown>;
  } catch (err) {
    logger.warn(`notifyNextEpisode: TMDB lookup failed for tmdbId=${tmdbId}`, err);
    return null;
  }
}

/** Resolves whether a show has an episode becoming available TODAY
 *  (`daysUntil === 0`), evaluating both `last_episode_to_air` and
 *  `next_episode_to_air` through the shared Trakt-air-time model — this is
 *  what lets a just-aired episode (already rolled off TMDB's
 *  `next_episode_to_air`) still trigger today's push. Returns `null` when
 *  neither candidate is available today, or when the TMDB lookup itself
 *  fails; a single show's Trakt/TMDB failure never aborts the batch. */
async function resolveTodayEpisode(
  tmdbId: number,
  apiKey: string,
  clientId: string,
  idCache: TraktIdCache,
  now: Date,
): Promise<NextEpisodeInfo | null> {
  const showJson = await fetchShowEpisodesPayload(tmdbId, apiKey);
  const candidates = candidateEpisodes(showJson);
  if (candidates.length === 0) return null;

  const resolveAirsAtUtc = async (candidate: EpisodeCandidate): Promise<Date | null> => {
    if (!clientId) return null;
    try {
      const traktShowId = await idCache.get(tmdbId, clientId);
      if (traktShowId == null) return null;
      return await fetchEpisodeFirstAired(
        traktShowId,
        candidate.season,
        candidate.number,
        clientId,
      );
    } catch (err) {
      logger.warn(`notifyNextEpisode: Trakt lookup failed for tmdbId=${tmdbId}`, err);
      return null;
    }
  };

  // windowAheadDays/windowBehindDays = 0 forces "only a candidate becoming
  // available EXACTLY today survives" — i.e. the `daysUntil === 0` gate.
  const best = await pickBestAvailability(candidates, resolveAirsAtUtc, {
    lagHours: UPNEXT_LAG_HOURS,
    now,
    windowAheadDays: 0,
    windowBehindDays: 0,
  });
  if (!best) return null;

  return {
    airDate: todayUtcIso(now),
    seasonNumber: best.candidate.season,
    episodeNumber: best.candidate.number,
    episodeName: best.candidate.name,
    hasTime: best.availability.hasTime,
    availableAt: best.availability.availableAt,
  };
}

/** Fan out per household. Exported for direct invocation in tests against
 *  the Firestore emulator if desired (not used today). */
async function notifyHousehold(
  db: admin.firestore.Firestore,
  hhId: string,
  apiKey: string,
  clientId: string,
  idCache: TraktIdCache,
  today: string,
  now: Date,
): Promise<{ pushed: number; skipped: number; errors: number }> {
  // 1. Read all in-progress TV watch entries.
  const entriesSnap = await db
    .collection(`households/${hhId}/watchEntries`)
    .where("media_type", "==", "tv")
    .where("in_progress_status", "==", "watching")
    .get();
  if (entriesSnap.empty) return { pushed: 0, skipped: 0, errors: 0 };

  const entries: (WatchEntryRow & { docRef: admin.firestore.DocumentReference })[] = [];
  for (const doc of entriesSnap.docs) {
    const data = doc.data();
    const tmdbId = data["tmdb_id"] as number | undefined;
    const title = data["title"] as string | undefined;
    if (!tmdbId || !title) continue;
    entries.push({
      entryId: doc.id,
      tmdbId,
      title,
      posterPath: (data["poster_path"] as string | null | undefined) ?? null,
      lastEpisodeNotifiedFor:
        (data["last_episode_notified_for"] as string | undefined) ?? undefined,
      docRef: doc.ref,
    });
  }
  if (entries.length === 0) return { pushed: 0, skipped: 0, errors: 0 };

  // 2. Resolve today's availability per show. Sequential with a small
  //    throttle — this CF runs once a day and TMDB/Trakt have soft
  //    per-IP caps; no need to fan out aggressively.
  const nextEpByTmdbId: Record<number, NextEpisodeInfo | null> = {};
  for (const e of entries) {
    try {
      nextEpByTmdbId[e.tmdbId] = await resolveTodayEpisode(
        e.tmdbId,
        apiKey,
        clientId,
        idCache,
        now,
      );
    } catch (err) {
      // A single show's failure must never abort the batch.
      logger.warn(`notifyNextEpisode: resolution failed for tmdbId=${e.tmdbId}`, err);
      nextEpByTmdbId[e.tmdbId] = null;
    }
  }

  // 3. Decide who needs a push (pure).
  const toNotify = pickEntriesNeedingNotify(today, entries, nextEpByTmdbId);
  if (toNotify.length === 0) return { pushed: 0, skipped: entries.length, errors: 0 };

  // 4. Read household member tokens.
  const membersSnap = await db.collection(`households/${hhId}/members`).get();
  const tokens: string[] = [];
  for (const m of membersSnap.docs) {
    const t = m.data()["fcm_token"] as string | undefined;
    if (t) tokens.push(t);
  }
  if (tokens.length === 0) {
    logger.info(`notifyNextEpisode: hh=${hhId} has notifications to send but no tokens`);
    return { pushed: 0, skipped: entries.length, errors: 0 };
  }

  // 5. Send + stamp.
  let pushed = 0;
  let errors = 0;
  for (const n of toNotify) {
    const epLabel = formatEpisodeLabel(n.seasonNumber, n.episodeNumber);
    const bodyName = n.episodeName ? ` — ${n.episodeName}` : "";
    const body = `${n.showTitle} ${epLabel}${bodyName}`;
    const title = formatNotifyTitle(n.hasTime, n.availableAt, now);
    for (const token of tokens) {
      try {
        await admin.messaging().send({
          token,
          data: {
            type: "next_episode_today",
            media_type: "tv",
            tmdb_id: n.tmdbId.toString(),
            entry_id: n.entryId,
            season: n.seasonNumber.toString(),
            episode: n.episodeNumber.toString(),
            title: n.showTitle,
          },
          notification: {
            title,
            body,
          },
          android: { priority: "normal" },
        });
      } catch (err) {
        errors++;
        logger.warn(
          `notifyNextEpisode: FCM send failed for hh=${hhId} entry=${n.entryId}`,
          err,
        );
      }
    }
    // Stamp the air date even if some tokens failed — partial-fail still
    // counts as "we tried", and we'd rather not duplicate-push later.
    try {
      await db
        .doc(`households/${hhId}/watchEntries/${n.entryId}`)
        .update({ last_episode_notified_for: n.airDate });
      pushed++;
    } catch (err) {
      errors++;
      logger.warn(
        `notifyNextEpisode: stamp failed for hh=${hhId} entry=${n.entryId}`,
        err,
      );
    }
  }
  return { pushed, skipped: entries.length - toNotify.length, errors };
}

/**
 * Scheduled at 09:00 UTC daily — far enough into the day that TMDB's
 * `next_episode_to_air.air_date` has rolled over for major release
 * regions, but still early enough that European/UK households see the
 * push at a reasonable morning hour. (UK = 09:00 BST / 10:00 GMT.)
 */
export const notifyNextEpisodeDaily = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "Etc/UTC",
    region: "europe-west2",
    secrets: [TMDB_API_KEY, TRAKT_CLIENT_ID],
  },
  async () => {
    const apiKey = TMDB_API_KEY.value();
    if (!apiKey) {
      logger.error("notifyNextEpisode: TMDB_API_KEY secret unset; skipping");
      return;
    }
    // Empty is a valid runtime state — resolveTodayEpisode treats an empty
    // clientId as "skip Trakt, use the date-only fallback" (same as a
    // Trakt outage would).
    const clientId = TRAKT_CLIENT_ID.value() ?? "";
    const now = new Date();
    const today = todayUtcIso(now);
    const idCache = createTraktIdCache();
    const db = admin.firestore();
    const hhSnap = await db.collection("households").get();
    let totalPushed = 0;
    let totalSkipped = 0;
    let totalErrors = 0;
    for (const hh of hhSnap.docs) {
      try {
        const r = await notifyHousehold(db, hh.id, apiKey, clientId, idCache, today, now);
        totalPushed += r.pushed;
        totalSkipped += r.skipped;
        totalErrors += r.errors;
      } catch (err) {
        totalErrors++;
        logger.warn(`notifyNextEpisode: hh=${hh.id} sweep failed`, err);
      }
    }
    logger.info("notifyNextEpisode sweep complete", {
      households: hhSnap.size,
      today,
      pushed: totalPushed,
      skipped: totalSkipped,
      errors: totalErrors,
    });
  },
);
