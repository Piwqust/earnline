// Conflict-safe, local-first sync shared by the secure proxy transport and the
// explicit development-only Supabase transport. The pass replays remote
// tombstones, pulls/conflict-checks, then pushes local deletes and dirty rows,
// and finally pulls the server-authored timestamps.

import type { Table } from "dexie";
import { getDatabase, type EarnlineDB } from "../data/db";
import type { Client, Entry, Heading, MonthReview, SyncEntity, SyncState, Tombstone } from "../domain/types";
import { needsSync, syncUpdatedAt } from "../domain/types";
import type { RowByTable, RowTable, SyncRemote } from "./remoteClient";
import {
  type ClientRow,
  type EntryRow,
  type HeadingRow,
  type MonthReviewRow,
  type TombstoneRow,
  type WorkspaceProfilePayload,
  type WorkspaceProfileRow,
  clientToRow,
  entryToRow,
  headingToRow,
  monthReviewToRow,
  parseTimestamp,
  rowToClient,
  rowToEntry,
  rowToHeading,
  rowToMonthReview,
  tableFor,
  tombstoneToRow,
} from "./remoteRecords";

const PAGE_SIZE = 1000;

export type ConflictResolution = "requireUserChoice" | "preferLocal" | "preferRemote";

export class SyncConflictError extends Error {
  readonly count: number;

  constructor(count: number) {
    super(
      `Cloud data changed while this browser had ${count} unsynced ${count === 1 ? "change" : "changes"}. ` +
      "Choose which copy to keep before syncing.",
    );
    this.name = "SyncConflictError";
    this.count = count;
  }
}

interface SyncOptions {
  database?: EarnlineDB;
  signal?: AbortSignal;
  conflictResolution?: ConflictResolution;
}

function throwIfAborted(signal?: AbortSignal): void {
  signal?.throwIfAborted();
}

export async function syncWorkspaceProfile(
  remote: SyncRemote,
  local: WorkspaceProfilePayload,
  pushLocal: boolean,
  signal?: AbortSignal,
): Promise<WorkspaceProfileRow> {
  const existing = await remote.fetchProfile(signal);
  if (!pushLocal && existing) return existing;
  return remote.upsertProfile({ ...local, workspace_id: remote.rowWorkspace }, signal);
}

export async function sync(
  remote: SyncRemote,
  lastPulledMs: number | null,
  options: SyncOptions = {},
): Promise<number | null> {
  const database = options.database ?? getDatabase();
  const resolution = options.conflictResolution ?? "requireUserChoice";
  const signal = options.signal;
  throwIfAborted(signal);

  const remoteTombstones = await fetchRows(remote, "earnline_tombstones", "deleted_at", null, signal);
  await applyRemoteTombstones(remoteTombstones, database, resolution, signal);
  const remoteDeletionTimes = latestRemoteDeletionTimes(remoteTombstones);

  // Read and resolve cloud edits before sending local deletes or dirty rows.
  // Otherwise a reconnecting browser can destroy a newer edit before it ever
  // has a chance to detect the conflict.
  const maxBeforePush = await pullRemoteRows(
    remote,
    database,
    lastPulledMs,
    remoteDeletionTimes,
    resolution,
    signal,
  );
  await pushDeletes(remote, database, signal);
  await pushLocalRows(remote, database, signal);
  const maxAfterPush = await pullRemoteRows(
    remote,
    database,
    lastPulledMs,
    remoteDeletionTimes,
    resolution,
    signal,
  );

  const observed = Math.max(maxBeforePush, maxAfterPush);
  return observed > 0 ? Math.max(observed, lastPulledMs ?? 0) : lastPulledMs;
}

function hasDirtyConflict(
  remoteUpdatedMs: number,
  local: { syncState: SyncState; lastSyncedAt?: number | null },
): boolean {
  if (local.syncState === "synced") return false;
  if (local.lastSyncedAt == null) return true;
  return remoteUpdatedMs > local.lastSyncedAt;
}

function syncKey(entity: SyncEntity, recordId: string): string {
  return `${entity}:${recordId}`;
}

function hasDeleteConflict(remoteUpdatedMs: number, tombstone: Tombstone): boolean {
  return tombstone.lastSyncedAt == null || remoteUpdatedMs > tombstone.lastSyncedAt;
}

function latestRemoteDeletionTimes(rows: TombstoneRow[]): ReadonlyMap<string, number> {
  const output = new Map<string, number>();
  for (const row of rows) {
    const deletedAt = parseTimestamp(row.deleted_at);
    if (deletedAt == null) continue;
    const key = syncKey(row.entity, row.record_id);
    output.set(key, Math.max(output.get(key) ?? 0, deletedAt));
  }
  return output;
}

function tombstoneApplies(
  deletedAt: number,
  local: { syncState: SyncState; lastSyncedAt?: number | null; updatedAt?: number | null; createdAt: number },
  resolution: ConflictResolution,
): boolean {
  if (local.syncState !== "synced") return resolution === "preferRemote" && hasDirtyConflict(deletedAt, local);
  return deletedAt >= (local.lastSyncedAt ?? syncUpdatedAt(local));
}

async function applyRemoteTombstones(
  rows: TombstoneRow[],
  database: EarnlineDB,
  resolution: ConflictResolution,
  signal?: AbortSignal,
): Promise<void> {
  if (rows.length === 0) return;
  await database.transaction("rw", database.clients, database.headings, database.entries, async () => {
    const clientIds = rows.filter((r) => r.entity === "client").map((r) => r.record_id);
    const headingIds = rows.filter((r) => r.entity === "heading").map((r) => r.record_id);
    const entryIds = rows.filter((r) => r.entity === "entry").map((r) => r.record_id);
    const [clients, headings, entries] = await Promise.all([
      database.clients.bulkGet(clientIds), database.headings.bulkGet(headingIds), database.entries.bulkGet(entryIds),
    ]);
    const clientsById = new Map(clients.filter((v): v is Client => v != null).map((v) => [v.id, v]));
    const headingsById = new Map(headings.filter((v): v is Heading => v != null).map((v) => [v.id, v]));
    const entriesById = new Map(entries.filter((v): v is Entry => v != null).map((v) => [v.id, v]));

    let conflicts = 0;
    for (const row of rows) {
      const deletedAt = parseTimestamp(row.deleted_at);
      if (deletedAt == null) continue;
      const local = row.entity === "client" ? clientsById.get(row.record_id)
        : row.entity === "heading" ? headingsById.get(row.record_id)
          : entriesById.get(row.record_id);
      if (local && hasDirtyConflict(deletedAt, local)) conflicts += 1;
    }
    if (conflicts > 0 && resolution === "requireUserChoice") throw new SyncConflictError(conflicts);

    for (const row of rows) {
      throwIfAborted(signal);
      const deletedAt = parseTimestamp(row.deleted_at);
      if (deletedAt == null) continue;
      if (row.entity === "client") {
        const local = clientsById.get(row.record_id);
        if (local && tombstoneApplies(deletedAt, local, resolution)) {
          await database.clients.delete(local.id);
          const owned = await database.entries.where("clientId").equals(local.id).primaryKeys();
          await database.entries.bulkDelete(owned as string[]);
        }
      } else if (row.entity === "heading") {
        const local = headingsById.get(row.record_id);
        if (local && tombstoneApplies(deletedAt, local, resolution)) await database.headings.delete(local.id);
      } else {
        const local = entriesById.get(row.record_id);
        if (local && tombstoneApplies(deletedAt, local, resolution)) await database.entries.delete(local.id);
      }
    }
  });
}

async function pushDeletes(remote: SyncRemote, database: EarnlineDB, signal?: AbortSignal): Promise<void> {
  const tombstones = await database.tombstones.toArray();
  if (tombstones.length === 0) return;
  await remote.upsertRows(
    "earnline_tombstones",
    tombstones.map((row) => tombstoneToRow(row, remote.rowWorkspace)),
    signal,
  );

  const groups = new Map<(typeof tombstones)[number]["entity"], typeof tombstones>();
  for (const row of tombstones) groups.set(row.entity, [...(groups.get(row.entity) ?? []), row]);
  for (const [entity, group] of groups) {
    throwIfAborted(signal);
    await remote.deleteRows(tableFor(entity), group.map((row) => row.recordId), signal);
    await database.tombstones.bulkDelete(group.map((row) => row.id));
  }
}

async function pushLocalRows(remote: SyncRemote, database: EarnlineDB, signal?: AbortSignal): Promise<void> {
  const clients = await database.clients.where("syncState").notEqual("synced").toArray();
  if (clients.length > 0) {
    await remote.upsertRows("earnline_clients", clients.map((row) => clientToRow(row, remote.rowWorkspace)), signal);
    await markPushed(database, database.clients, clients);
  }
  const headings = await database.headings.where("syncState").notEqual("synced").toArray();
  if (headings.length > 0) {
    await remote.upsertRows("earnline_headings", headings.map((row) => headingToRow(row, remote.rowWorkspace)), signal);
    await markPushed(database, database.headings, headings);
  }
  const entries = await database.entries.where("syncState").notEqual("synced").toArray();
  if (entries.length > 0) {
    await remote.upsertRows("earnline_entries", entries.map((row) => entryToRow(row, remote.rowWorkspace)), signal);
    await markPushed(database, database.entries, entries);
  }
  const monthReviews = await database.monthReviews.where("syncState").notEqual("synced").toArray();
  if (monthReviews.length > 0) {
    await remote.upsertRows(
      "earnline_month_reviews",
      monthReviews.map((row) => monthReviewToRow(row, remote.rowWorkspace)),
      signal,
    );
    await markPushed(database, database.monthReviews, monthReviews);
  }
}

async function markPushed<
  T extends { id: string; syncState: SyncState; updatedAt?: number | null; createdAt: number; lastSyncedAt?: number | null },
>(database: EarnlineDB, table: Table<T, string>, pushed: T[]): Promise<void> {
  await database.transaction("rw", table, async () => {
    for (const row of pushed) {
      const current = await table.get(row.id);
      if (current && needsSync(current) && syncUpdatedAt(current) === syncUpdatedAt(row)) {
        // The following pull records the server baseline. Nil fails closed if
        // the app is interrupted between this write and that pull.
        await table.put({ ...current, syncState: "synced", lastSyncedAt: null });
      }
    }
  });
}

async function pullRemoteRows(
  remote: SyncRemote,
  database: EarnlineDB,
  lastPulledMs: number | null,
  remoteDeletionTimes: ReadonlyMap<string, number>,
  resolution: ConflictResolution,
  signal?: AbortSignal,
): Promise<number> {
  const [clientCount, headingCount, entryCount, monthReviewCount] = await Promise.all([
    database.clients.count(), database.headings.count(), database.entries.count(), database.monthReviews.count(),
  ]);
  const [remoteClients, remoteHeadings, remoteEntries, remoteMonthReviews] = await Promise.all([
    fetchRows(remote, "earnline_clients", "updated_at", clientCount === 0 ? null : lastPulledMs, signal),
    fetchRows(remote, "earnline_headings", "updated_at", headingCount === 0 ? null : lastPulledMs, signal),
    fetchRows(remote, "earnline_entries", "updated_at", entryCount === 0 ? null : lastPulledMs, signal),
    fetchRows(remote, "earnline_month_reviews", "updated_at", monthReviewCount === 0 ? null : lastPulledMs, signal),
  ]);
  const maxUpdatedAt = [...remoteClients, ...remoteHeadings, ...remoteEntries, ...remoteMonthReviews].reduce((max, row) => {
    const value = parseTimestamp(row.updated_at);
    return value == null ? max : Math.max(max, value);
  }, 0);

  // A retained tombstone is authoritative until a row is explicitly restored
  // with a newer server timestamp. This prevents a row left behind by a
  // partially completed delete from being resurrected on another device.
  const clientsToApply = remoteClients.filter((row) => {
    const updatedAt = parseTimestamp(row.updated_at) ?? 0;
    return updatedAt > (remoteDeletionTimes.get(syncKey("client", row.id)) ?? 0);
  });
  const headingsToApply = remoteHeadings.filter((row) => {
    const updatedAt = parseTimestamp(row.updated_at) ?? 0;
    return updatedAt > (remoteDeletionTimes.get(syncKey("heading", row.id)) ?? 0);
  });
  const entriesToApply = remoteEntries.filter((row) => {
    const updatedAt = parseTimestamp(row.updated_at) ?? 0;
    return updatedAt > (remoteDeletionTimes.get(syncKey("entry", row.id)) ?? 0);
  });

  await database.transaction(
    "rw",
    database.clients,
    database.headings,
    database.entries,
    database.monthReviews,
    database.tombstones,
    async () => {
    const [localClients, localHeadings, localEntries, localMonthReviews, localTombstones] = await Promise.all([
      database.clients.toArray(), database.headings.bulkGet(headingsToApply.map((r) => r.id)),
      database.entries.bulkGet(entriesToApply.map((r) => r.id)),
      database.monthReviews.bulkGet(remoteMonthReviews.map((r) => r.id)),
      database.tombstones.toArray(),
    ]);
    const clientsById = new Map(localClients.map((row) => [row.id, row]));
    const headingsById = new Map(localHeadings.filter((v): v is Heading => v != null).map((row) => [row.id, row]));
    const entriesById = new Map(localEntries.filter((v): v is Entry => v != null).map((row) => [row.id, row]));
    const monthReviewsById = new Map(
      localMonthReviews.filter((v): v is MonthReview => v != null).map((row) => [row.id, row]),
    );
    const pendingDeletes = new Map(localTombstones.map((row) => [syncKey(row.entity, row.recordId), row]));

    let conflicts = 0;
    for (const row of clientsToApply) {
      const local = clientsById.get(row.id);
      const updated = parseTimestamp(row.updated_at);
      const pendingDelete = pendingDeletes.get(syncKey("client", row.id));
      if (updated != null && pendingDelete && hasDeleteConflict(updated, pendingDelete)) conflicts += 1;
      else if (local && updated != null && hasDirtyConflict(updated, local)) conflicts += 1;
    }
    for (const row of headingsToApply) {
      const local = headingsById.get(row.id);
      const updated = parseTimestamp(row.updated_at);
      const pendingDelete = pendingDeletes.get(syncKey("heading", row.id));
      if (updated != null && pendingDelete && hasDeleteConflict(updated, pendingDelete)) conflicts += 1;
      else if (local && updated != null && hasDirtyConflict(updated, local)) conflicts += 1;
    }
    for (const row of entriesToApply) {
      const local = entriesById.get(row.id);
      const updated = parseTimestamp(row.updated_at);
      const pendingDelete = pendingDeletes.get(syncKey("entry", row.id));
      if (updated != null && pendingDelete && hasDeleteConflict(updated, pendingDelete)) conflicts += 1;
      else if (local && updated != null && hasDirtyConflict(updated, local)) conflicts += 1;
    }
    for (const row of remoteMonthReviews) {
      const local = monthReviewsById.get(row.id);
      const updated = parseTimestamp(row.updated_at);
      if (local && updated != null && hasDirtyConflict(updated, local)) conflicts += 1;
    }
    if (conflicts > 0 && resolution === "requireUserChoice") throw new SyncConflictError(conflicts);

    async function permitsRemoteRow(entity: SyncEntity, id: string, updatedAt: number | null): Promise<boolean> {
      const key = syncKey(entity, id);
      const pendingDelete = pendingDeletes.get(key);
      if (!pendingDelete) return true;
      if (updatedAt != null && hasDeleteConflict(updatedAt, pendingDelete) && resolution === "preferRemote") {
        await database.tombstones.delete(pendingDelete.id);
        pendingDeletes.delete(key);
        return true;
      }
      return false;
    }

    for (const row of clientsToApply) {
      throwIfAborted(signal);
      const updated = parseTimestamp(row.updated_at);
      if (!(await permitsRemoteRow("client", row.id, updated))) continue;
      const local = clientsById.get(row.id);
      if (local && local.syncState !== "synced") {
        if (resolution !== "preferRemote" || updated == null || !hasDirtyConflict(updated, local)) continue;
      }
      const decoded = rowToClient(row, Date.now());
      await database.clients.put(decoded);
      clientsById.set(row.id, decoded);
    }
    for (const row of headingsToApply) {
      throwIfAborted(signal);
      const updated = parseTimestamp(row.updated_at);
      if (!(await permitsRemoteRow("heading", row.id, updated))) continue;
      const local = headingsById.get(row.id);
      if (local && local.syncState !== "synced") {
        if (resolution !== "preferRemote" || updated == null || !hasDirtyConflict(updated, local)) continue;
      }
      const decoded = rowToHeading(row, Date.now());
      await database.headings.put(decoded);
      headingsById.set(row.id, decoded);
    }
    for (const row of entriesToApply) {
      throwIfAborted(signal);
      const updated = parseTimestamp(row.updated_at);
      if (!(await permitsRemoteRow("entry", row.id, updated))) continue;
      if (!clientsById.has(row.client_id)) continue;
      const local = entriesById.get(row.id);
      if (local && local.syncState !== "synced") {
        if (resolution !== "preferRemote" || updated == null || !hasDirtyConflict(updated, local)) continue;
      }
      const decoded = rowToEntry(row, Date.now());
      await database.entries.put(decoded);
      entriesById.set(row.id, decoded);
    }
    for (const row of remoteMonthReviews) {
      throwIfAborted(signal);
      const updated = parseTimestamp(row.updated_at);
      const local = monthReviewsById.get(row.id);
      if (local && local.syncState !== "synced") {
        if (resolution !== "preferRemote" || updated == null || !hasDirtyConflict(updated, local)) continue;
      }
      const decoded = rowToMonthReview(row, Date.now());
      await database.monthReviews.put(decoded);
      monthReviewsById.set(row.id, decoded);
    }
  },
  );
  return maxUpdatedAt;
}

async function fetchRows<T extends RowTable>(
  remote: SyncRemote,
  table: T,
  cursorColumn: T extends "earnline_tombstones" ? "deleted_at" : "updated_at",
  sinceMs: number | null,
  signal?: AbortSignal,
): Promise<RowByTable[T][]> {
  const output: RowByTable[T][] = [];
  let after: { timestamp: string; id: string } | null = null;
  for (;;) {
    throwIfAborted(signal);
    const page = await remote.fetchPage(table, cursorColumn, sinceMs, after, PAGE_SIZE, signal);
    output.push(...page);
    if (page.length < PAGE_SIZE) return output;
    const last = page.at(-1) as unknown as Record<string, unknown> | undefined;
    const timestamp = last?.[cursorColumn];
    if (!last || typeof timestamp !== "string" || typeof last.id !== "string") {
      throw new Error(`The sync service returned an invalid ${cursorColumn} cursor.`);
    }
    const next = { timestamp, id: last.id };
    if (after?.timestamp === next.timestamp && after.id === next.id) {
      throw new Error(`The sync service repeated a ${cursorColumn} cursor.`);
    }
    after = next;
  }
}

// Exported only for focused conflict-policy tests.
export const syncPolicy = { hasDirtyConflict, hasDeleteConflict, tombstoneApplies };

// Keep these DTO types in the generated declaration surface for consumers.
export type SyncRows = ClientRow | EntryRow | HeadingRow | MonthReviewRow;
