/**
 * Per-user daily rate limiter. The actual guarantees we care about:
 *
 *   1. Under the limit → request goes through, counter increments.
 *   2. At the limit → request throws resource-exhausted; counter does NOT
 *      advance (Firestore transaction throws before tx.set fires).
 *   3. Window-expiry resets the counter even mid-stream.
 *   4. Per-kind isolation — concierge and scoreRecommendations counters
 *      can't poison each other.
 *   5. Window-start timestamp is set once per window, not slid forward
 *      on every increment (otherwise a steady stream of calls would
 *      forever postpone the reset).
 */
import { checkAndIncrement } from "../src/rateLimit";

jest.mock("firebase-admin", () => {
  class FakeTimestamp {
    constructor(public ms: number) {}
    toMillis() { return this.ms; }
    static fromMillis(ms: number) { return new FakeTimestamp(ms); }
  }
  return {
    firestore: Object.assign(() => (globalThis as any).__FAKE_DB, {
      Timestamp: FakeTimestamp,
    }),
  };
});

interface StoredDoc {
  [key: string]: number | { toMillis: () => number };
}

function makeDb(initial: StoredDoc = {}) {
  let stored: StoredDoc | undefined = Object.keys(initial).length
    ? { ...initial }
    : undefined;
  const writes: StoredDoc[] = [];
  const runTransaction = jest
    .fn()
    .mockImplementation(async (fn: (tx: any) => Promise<any>) => {
      const tx = {
        get: jest.fn().mockResolvedValue({
          exists: !!stored,
          data: () => stored,
        }),
        set: jest.fn().mockImplementation((_ref: any, payload: StoredDoc) => {
          stored = { ...(stored ?? {}), ...payload };
          writes.push(payload);
        }),
      };
      return fn(tx);
    });
  const doc = jest.fn().mockReturnValue({});
  return {
    runTransaction,
    doc,
    _peek: () => stored,
    _writes: writes,
  } as any;
}

beforeEach(() => {
  jest.spyOn(Date, "now").mockReturnValue(1_700_000_000_000);
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("checkAndIncrement", () => {
  test("first call opens the window and increments to 1", async () => {
    const db = makeDb();
    (globalThis as any).__FAKE_DB = db;
    await checkAndIncrement("user1", "concierge", 3);
    expect(db._peek().concierge_count).toBe(1);
    expect(db._peek().concierge_window_start.toMillis())
      .toBe(1_700_000_000_000);
  });

  test("under the limit — counter increments without throwing", async () => {
    const db = makeDb({
      concierge_count: 2,
      concierge_window_start: { toMillis: () => 1_700_000_000_000 },
    });
    (globalThis as any).__FAKE_DB = db;
    await checkAndIncrement("user1", "concierge", 5);
    expect(db._peek().concierge_count).toBe(3);
  });

  test("at the limit — throws resource-exhausted, counter unchanged", async () => {
    const db = makeDb({
      concierge_count: 5,
      concierge_window_start: { toMillis: () => 1_700_000_000_000 },
    });
    (globalThis as any).__FAKE_DB = db;
    await expect(checkAndIncrement("user1", "concierge", 5))
      .rejects.toMatchObject({ code: "resource-exhausted" });
    expect(db._peek().concierge_count).toBe(5);
  });

  test("window-expiry resets the counter mid-stream", async () => {
    // Window opened 25h ago; new call past the 24h boundary resets.
    const ms25hAgo = 1_700_000_000_000 - 25 * 60 * 60 * 1000;
    const db = makeDb({
      concierge_count: 10,
      concierge_window_start: { toMillis: () => ms25hAgo },
    });
    (globalThis as any).__FAKE_DB = db;
    await checkAndIncrement("user1", "concierge", 5);
    // Counter reset to 1 (the current call) — old window expired.
    expect(db._peek().concierge_count).toBe(1);
    expect(db._peek().concierge_window_start.toMillis())
      .toBe(1_700_000_000_000);
  });

  test("per-kind isolation — concierge count doesn't affect score limit", async () => {
    const db = makeDb({
      concierge_count: 50,
      concierge_window_start: { toMillis: () => 1_700_000_000_000 },
    });
    (globalThis as any).__FAKE_DB = db;
    // scoreRecommendations counter is independent — should still increment
    // from 0 even though concierge has burned 50/50.
    await checkAndIncrement("user1", "scoreRecommendations", 10);
    expect(db._peek().scoreRecommendations_count).toBe(1);
    expect(db._peek().concierge_count).toBe(50);
  });

  test("window-start stays pinned across increments (doesn't slide)", async () => {
    const windowOpened = 1_700_000_000_000 - 60 * 60 * 1000; // 1h ago
    const db = makeDb({
      concierge_count: 5,
      concierge_window_start: { toMillis: () => windowOpened },
    });
    (globalThis as any).__FAKE_DB = db;
    await checkAndIncrement("user1", "concierge", 10);
    // Window start unchanged — reset only happens when WINDOW_MS elapses.
    // Naive impl that wrote `now` on every increment would let a steady
    // stream of calls forever postpone the reset.
    expect(db._peek().concierge_window_start.toMillis()).toBe(windowOpened);
    expect(db._peek().concierge_count).toBe(6);
  });
});
