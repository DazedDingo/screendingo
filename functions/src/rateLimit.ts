/**
 * Per-user daily rate limiter for Cloud Function entry points that spend
 * metered third-party quota (Gemini API, OMDb, etc).
 *
 * Why this exists: the app's free-tier Gemini quota is 1,500 req/day
 * total across all users. Without per-user caps, a single bad actor (or
 * a buggy reverse-engineered client) can exhaust the shared quota in
 * minutes — exposing the developer to spillover billing on the paid
 * tier and breaking the experience for every other user.
 *
 * Storage: `/userRateLimits/{uid}` doc with one field-pair per kind
 * (`${kind}_count: number`, `${kind}_window_start: Timestamp`). Locked
 * to admin-SDK only via Firestore rules — clients cannot read or write.
 *
 * Window: 24 hours rolling per user per kind. First call after a fresh
 * window opens the window; subsequent calls increment until the limit
 * is hit; the next call after the window expires resets.
 *
 * Throws `resource-exhausted` HttpsError when the limit is hit so the
 * client can render a helpful "Daily limit reached" message instead of
 * a generic failure. Includes the reset time in the error message for
 * the user-facing string.
 */
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

const WINDOW_MS = 24 * 60 * 60 * 1000; // 24h rolling window

/**
 * Atomically check + increment the per-user counter for [kind]. Throws
 * `resource-exhausted` if [uid] has already used [limit] calls in the
 * current 24h window.
 *
 * Safe to call concurrently — runs inside a Firestore transaction so two
 * simultaneous requests can't double-spend the same quota slot. Returns
 * normally on success (no value); callers don't need to inspect the
 * remaining count.
 */
export async function checkAndIncrement(
  uid: string,
  kind: string,
  limit: number,
): Promise<void> {
  const db = admin.firestore();
  const ref = db.doc(`userRateLimits/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const data = snap.data() ?? {};
    const countKey = `${kind}_count`;
    const startKey = `${kind}_window_start`;
    const windowStartTs = data[startKey] as
      | admin.firestore.Timestamp
      | undefined;
    const windowStart = windowStartTs?.toMillis() ?? 0;
    let count = (data[countKey] as number | undefined) ?? 0;

    if (now - windowStart >= WINDOW_MS) {
      // Window expired (or never opened) — reset.
      count = 0;
    }

    if (count >= limit) {
      const resetAt = new Date(
        windowStart > 0 ? windowStart + WINDOW_MS : now + WINDOW_MS,
      );
      throw new HttpsError(
        "resource-exhausted",
        `Daily ${kind} limit (${limit}) reached. Try again after ${resetAt.toISOString()}.`,
      );
    }

    // Bump count + persist window start. Set start fresh only when this
    // is the first call of a new window (count was 0 going in); otherwise
    // preserve the existing start so the window doesn't slide forward on
    // every call.
    const startToWrite = count === 0
      ? admin.firestore.Timestamp.fromMillis(now)
      : windowStartTs ?? admin.firestore.Timestamp.fromMillis(now);
    tx.set(
      ref,
      {
        [countKey]: count + 1,
        [startKey]: startToWrite,
      },
      { merge: true },
    );
  });
}

/**
 * Per-kind daily caps. Generous for a real household (a couple watching
 * every night barely hits 5-10 refreshes/day) but tight enough that one
 * abusive client can't burn the shared Gemini free tier.
 */
export const RATE_LIMITS = {
  concierge: 50, // chat messages + Like-these refreshes
  scoreRecommendations: 30, // each call = ~10 Gemini scoring batches
  externalRatings: 200, // OMDb fetches — only counted on cache MISS
} as const;
