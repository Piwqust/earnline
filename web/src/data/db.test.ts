import { afterEach, describe, expect, it } from "vitest";
import {
  EarnlineDB,
  activateDatabase,
  decodeRecoveryEnvelope,
  exportDatabase,
  getDatabase,
  getDatabaseGeneration,
  importDatabase,
} from "./db";
import type { Client } from "../domain/types";
import { monthReviewId } from "../domain/monthReview";

const opened: EarnlineDB[] = [];

function database(scope: string): EarnlineDB {
  const value = new EarnlineDB(`test-${scope}-${crypto.randomUUID()}`);
  opened.push(value);
  return value;
}

function client(id: string): Client {
  return { id, name: id, colorHex: "#0088FF", sortIndex: 0, createdAt: 1, updatedAt: 1,
    syncState: "dirty", lastSyncedAt: null };
}

afterEach(async () => {
  await Promise.all(opened.splice(0).map(async (db) => { db.close(); await db.delete(); }));
});

describe("connection-scoped IndexedDB", () => {
  it("keeps rows and cursors isolated", async () => {
    const first = database("first");
    const second = database("second");
    await first.clients.put(client("first-client"));
    await first.syncMetadata.put({ id: "sync", rowCursorMs: 123, lastSyncAt: 456 });
    expect(await second.clients.count()).toBe(0);
    expect(await second.syncMetadata.get("sync")).toBeUndefined();
  });

  it("exports and additively restores a recovery envelope as dirty", async () => {
    const source = database("source");
    const target = database("target");
    await source.clients.put(client("recover-me"));
    const monthStart = Date.UTC(2026, 0, 1);
    await source.monthReviews.put({
      id: monthReviewId(monthStart), monthStart, note: "January close", closedAt: Date.UTC(2026, 1, 1),
      createdAt: 1, updatedAt: 1, syncState: "synced", lastSyncedAt: 1,
    });
    const backup = await exportDatabase(source);
    const decoded = decodeRecoveryEnvelope(JSON.parse(JSON.stringify(backup)));
    await importDatabase(decoded, target);
    expect(await target.clients.get("recover-me")).toMatchObject({ syncState: "dirty" });
    expect(await target.monthReviews.get(monthReviewId(monthStart))).toMatchObject({ syncState: "dirty" });
  });

  it("lets only the newest overlapping activation replace the live database", async () => {
    const firstScope = `activation-first-${crypto.randomUUID()}`;
    const finalScope = `activation-final-${crypto.randomUUID()}`;
    const startingGeneration = getDatabaseGeneration();

    const [, activated] = await Promise.all([
      activateDatabase(firstScope),
      activateDatabase(finalScope),
    ]);

    expect(activated.scope).toBe(finalScope);
    expect(getDatabase().scope).toBe(finalScope);
    expect(getDatabaseGeneration()).toBe(startingGeneration + 1);

    await activateDatabase("local");
    for (const scope of [firstScope, finalScope]) {
      const cleanup = new EarnlineDB(scope);
      await cleanup.delete();
    }
  });
});
