import { describe, expect, it } from "vitest";
import { SyncGenerationGuard } from "./syncGeneration";

describe("sync generation guard", () => {
  it("aborts and rejects completion from the previous connection", () => {
    const first = {};
    const second = {};
    const guard = new SyncGenerationGuard<object>();
    const attempt = guard.begin(first);
    guard.invalidate();
    expect(attempt.signal.aborted).toBe(true);
    expect(guard.isCurrent(attempt, second)).toBe(false);
  });

  it("accepts only the current database resource", () => {
    const database = {};
    const guard = new SyncGenerationGuard<object>();
    const attempt = guard.begin(database);
    expect(guard.isCurrent(attempt, database)).toBe(true);
    expect(guard.isCurrent(attempt, {})).toBe(false);
  });
});
