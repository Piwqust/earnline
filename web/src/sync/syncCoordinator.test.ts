import { afterEach, describe, expect, it } from "vitest";
import { EarnlineDB } from "../data/db";
import type { Client, Entry } from "../domain/types";
import type { CursorColumn, RemoteValidation, RowByTable, RowTable, SyncRemote } from "./remoteClient";
import type { WorkspaceProfilePayload, WorkspaceProfileRow } from "./remoteRecords";
import { SyncConflictError, sync } from "./syncCoordinator";

const BASE = Date.UTC(2026, 0, 1);
const opened: EarnlineDB[] = [];

class FakeRemote implements SyncRemote {
  readonly rowWorkspace = "opaque";
  readonly transport = "proxy" as const;
  now = BASE + 10_000;
  log: string[] = [];
  rows: { [T in RowTable]: RowByTable[T][] } = {
    earnline_clients: [], earnline_entries: [], earnline_headings: [], earnline_tombstones: [],
  };

  async validate(): Promise<RemoteValidation> { return { scope: "scope", transport: "proxy" }; }
  async fetchProfile(): Promise<WorkspaceProfileRow | null> { return null; }
  async upsertProfile(payload: WorkspaceProfilePayload): Promise<WorkspaceProfileRow> {
    return { ...payload, updated_at: new Date(this.now++).toISOString() };
  }
  async fetchPage<T extends RowTable>(table: T, cursor: CursorColumn, since: number | null, from: number, limit: number): Promise<RowByTable[T][]> {
    this.log.push(`fetch:${table}`);
    return (this.rows[table] as RowByTable[T][])
      .filter((row) => since == null || Date.parse(String((row as unknown as Record<string, unknown>)[cursor])) >= since)
      .slice(from, from + limit);
  }
  async upsertRows<T extends RowTable>(table: T, rows: RowByTable[T][]): Promise<void> {
    this.log.push(`upsert:${table}`);
    const target = this.rows[table] as RowByTable[T][];
    for (const row of rows) {
      const stamped = { ...row } as RowByTable[T];
      if (table === "earnline_tombstones") {
        (stamped as unknown as { deleted_at: string }).deleted_at = new Date(this.now++).toISOString();
      } else {
        (stamped as unknown as { updated_at: string }).updated_at = new Date(this.now++).toISOString();
      }
      const index = target.findIndex((item) => item.id === row.id);
      if (index >= 0) target[index] = stamped; else target.push(stamped);
    }
  }
  async deleteRows(table: Exclude<RowTable, "earnline_tombstones">, ids: string[]): Promise<void> {
    this.log.push(`delete:${table}`);
    this.rows[table] = this.rows[table].filter((row) => !ids.includes(row.id)) as never;
  }
}

function database(): EarnlineDB {
  const value = new EarnlineDB(`sync-test-${crypto.randomUUID()}`);
  opened.push(value);
  return value;
}

function localClient(syncState: Client["syncState"] = "synced"): Client {
  return { id: "client-1", name: "Local", colorHex: "#0088FF", sortIndex: 0, createdAt: BASE,
    updatedAt: BASE, syncState, lastSyncedAt: BASE };
}

function localEntry(syncState: Entry["syncState"] = "dirty"): Entry {
  return { id: "entry-1", clientId: "client-1", amountCents: 10000, currencyCode: "USD", project: null,
    task: "Local edit", date: BASE, holdUntil: null, status: "paid", sortIndex: 0, createdAt: BASE,
    updatedAt: BASE + 100, syncState, lastSyncedAt: BASE };
}

function remoteClient(updated = BASE) {
  return { id: "client-1", workspace_id: "opaque", name: "Remote", color_hex: "#0088FF", sort_index: 0,
    created_at: new Date(BASE).toISOString(), updated_at: new Date(updated).toISOString() };
}

function remoteEntry(updated = BASE + 500) {
  return { id: "entry-1", workspace_id: "opaque", client_id: "client-1", amount: "200.00", currency_code: "USD",
    project: null, task: "Remote edit", date: "2026-01-01", hold_until: null, status: "paid" as const, sort_index: 0,
    created_at: new Date(BASE).toISOString(), updated_at: new Date(updated).toISOString() };
}

afterEach(async () => {
  await Promise.all(opened.splice(0).map(async (db) => { db.close(); await db.delete(); }));
});

describe("sync coordinator", () => {
  it("pulls first and stops before push on a newer remote conflict", async () => {
    const db = database();
    await db.clients.put(localClient());
    await db.entries.put(localEntry());
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_entries = [remoteEntry()];

    await expect(sync(remote, BASE, { database: db })).rejects.toBeInstanceOf(SyncConflictError);
    expect(remote.log.indexOf("fetch:earnline_entries")).toBeGreaterThanOrEqual(0);
    expect(remote.log.some((item) => item.startsWith("upsert:earnline_entries"))).toBe(false);
    expect(await db.entries.get("entry-1")).toMatchObject({ task: "Local edit", syncState: "dirty" });
  });

  it("pushes only after explicit local resolution and records the server baseline", async () => {
    const db = database();
    await db.clients.put(localClient());
    await db.entries.put(localEntry());
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_entries = [remoteEntry()];

    const cursor = await sync(remote, BASE, { database: db, conflictResolution: "preferLocal" });
    const stored = await db.entries.get("entry-1");
    expect(stored).toMatchObject({ task: "Local edit", syncState: "synced" });
    expect(stored?.lastSyncedAt).toBeGreaterThan(BASE);
    expect(cursor).toBeGreaterThan(BASE);
  });

  it("replays all tombstones even when the row cursor is newer", async () => {
    const db = database();
    await db.clients.put(localClient());
    await db.entries.put(localEntry("synced"));
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_tombstones = [{ id: "delete-1", workspace_id: "opaque", entity: "entry", record_id: "entry-1",
      deleted_at: new Date(BASE + 5).toISOString(), created_at: new Date(BASE + 5).toISOString() }];

    await sync(remote, BASE + 100_000, { database: db });
    expect(await db.entries.get("entry-1")).toBeUndefined();
  });

  it("applies the remote copy only after explicit cloud resolution", async () => {
    const db = database();
    await db.clients.put(localClient());
    await db.entries.put(localEntry());
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_entries = [remoteEntry()];
    await sync(remote, BASE, { database: db, conflictResolution: "preferRemote" });
    expect(await db.entries.get("entry-1")).toMatchObject({ task: "Remote edit", amountCents: 20000, syncState: "synced" });
  });

  it("does not let an older retained tombstone delete a newer restored row", async () => {
    const db = database();
    const restored = localEntry("synced");
    restored.updatedAt = BASE + 1_000;
    restored.lastSyncedAt = BASE + 1_000;
    await db.clients.put(localClient());
    await db.entries.put(restored);
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient(BASE + 1_000)];
    remote.rows.earnline_entries = [remoteEntry(BASE + 1_000)];
    remote.rows.earnline_tombstones = [{ id: "old-delete", workspace_id: "opaque", entity: "entry", record_id: "entry-1",
      deleted_at: new Date(BASE + 100).toISOString(), created_at: new Date(BASE + 100).toISOString() }];
    await sync(remote, BASE, { database: db });
    expect(await db.entries.get("entry-1")).toBeDefined();
  });

  it("stops before pushing a local delete when the cloud row changed", async () => {
    const db = database();
    await db.clients.put(localClient());
    await db.tombstones.put({
      id: "local-delete",
      entity: "entry",
      recordId: "entry-1",
      deletedAt: BASE + 100,
      createdAt: BASE + 100,
      lastSyncedAt: BASE,
    });
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_entries = [remoteEntry(BASE + 500)];

    await expect(sync(remote, BASE, { database: db })).rejects.toBeInstanceOf(SyncConflictError);
    expect(remote.rows.earnline_entries).toHaveLength(1);
    expect(remote.log).not.toContain("upsert:earnline_tombstones");
    expect(remote.log).not.toContain("delete:earnline_entries");
    expect(await db.tombstones.get("local-delete")).toBeDefined();
  });

  it("restores a remotely edited row after explicit cloud delete-conflict resolution", async () => {
    const db = database();
    await db.clients.put(localClient());
    await db.tombstones.put({
      id: "local-delete",
      entity: "entry",
      recordId: "entry-1",
      deletedAt: BASE + 100,
      createdAt: BASE + 100,
      lastSyncedAt: BASE,
    });
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_entries = [remoteEntry(BASE + 500)];

    await sync(remote, BASE, { database: db, conflictResolution: "preferRemote" });
    expect(await db.entries.get("entry-1")).toMatchObject({ task: "Remote edit", syncState: "synced" });
    expect(await db.tombstones.get("local-delete")).toBeUndefined();
    expect(remote.log).not.toContain("delete:earnline_entries");
  });

  it("does not resurrect a stale remote row left behind after a tombstone write", async () => {
    const db = database();
    await db.clients.put(localClient());
    const remote = new FakeRemote();
    remote.rows.earnline_clients = [remoteClient()];
    remote.rows.earnline_entries = [remoteEntry(BASE + 500)];
    remote.rows.earnline_tombstones = [{
      id: "remote-delete",
      workspace_id: "opaque",
      entity: "entry",
      record_id: "entry-1",
      deleted_at: new Date(BASE + 800).toISOString(),
      created_at: new Date(BASE + 800).toISOString(),
    }];

    await sync(remote, BASE, { database: db });
    expect(await db.entries.get("entry-1")).toBeUndefined();
  });
});
