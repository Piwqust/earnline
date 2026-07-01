// Faithful port of iOS Sync/SyncCoordinator.swift.
//
// Order (matters): push tombstones → push dirty rows → pull remote (last-write-
// wins on updated_at) → prune old tombstones. In this personal no-login model a
// local delete intentionally wins over a concurrent remote update.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Table } from "dexie";
import { db } from "../data/db";
import type { Client, Entry, Heading, SyncState } from "../domain/types";
import { needsSync, statusFromSyncRawValue, syncUpdatedAt } from "../domain/types";
import { centsFromWire } from "../domain/money";
import {
  type ClientRow,
  type EntryRow,
  type HeadingRow,
  type TombstoneRow,
  clientToRow,
  entryToRow,
  headingToRow,
  parseDay,
  parseTimestamp,
  rowToClient,
  rowToEntry,
  rowToHeading,
  tableFor,
  timestampString,
  tombstoneToRow,
} from "./remoteRecords";

const TOMBSTONE_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
const PAGE_SIZE = 1000;

export async function sync(
  supabase: SupabaseClient,
  workspaceId: string,
  lastPulledMs: number | null,
): Promise<number> {
  const syncedAt = Date.now();
  await pushDeletes(supabase, workspaceId);
  await pushLocalRows(supabase, workspaceId, syncedAt);
  await pullRemoteRows(supabase, workspaceId, lastPulledMs, syncedAt);
  await pruneRemoteTombstones(supabase, workspaceId, syncedAt);
  return syncedAt;
}

// --- push deletes ---

async function pushDeletes(supabase: SupabaseClient, workspaceId: string): Promise<void> {
  const tombstones = await db.tombstones.toArray();
  if (tombstones.length === 0) return;

  const rows = tombstones.map((t) => tombstoneToRow(t, workspaceId));
  const upsert = await supabase.from("earnline_tombstones").upsert(rows);
  if (upsert.error) throw upsert.error;

  for (const t of tombstones) {
    const del = await supabase
      .from(tableFor(t.entity))
      .delete()
      .eq("id", t.recordId)
      .eq("workspace_id", workspaceId);
    if (del.error) throw del.error;
    await db.tombstones.delete(t.id);
  }
}

// --- push local dirty rows ---

async function pushLocalRows(
  supabase: SupabaseClient,
  workspaceId: string,
  syncedAt: number,
): Promise<void> {
  const clients = (await db.clients.toArray()).filter(needsSync);
  if (clients.length) {
    const res = await supabase.from("earnline_clients").upsert(clients.map((c) => clientToRow(c, workspaceId)));
    if (res.error) throw res.error;
    await markSynced(db.clients, clients, syncedAt);
  }

  const headings = (await db.headings.toArray()).filter(needsSync);
  if (headings.length) {
    const res = await supabase.from("earnline_headings").upsert(headings.map((h) => headingToRow(h, workspaceId)));
    if (res.error) throw res.error;
    await markSynced(db.headings, headings, syncedAt);
  }

  const entries = (await db.entries.toArray()).filter(needsSync);
  if (entries.length) {
    const res = await supabase.from("earnline_entries").upsert(entries.map((e) => entryToRow(e, workspaceId)));
    if (res.error) throw res.error;
    await markSynced(db.entries, entries, syncedAt);
  }
}

/** Mark pushed rows synced — but only if the user hasn't edited them since. */
async function markSynced<
  T extends { id: string; syncState: SyncState; updatedAt?: number | null; createdAt: number; lastSyncedAt?: number | null },
>(table: Table<T, string>, pushed: T[], syncedAt: number): Promise<void> {
  await db.transaction("rw", table, async () => {
    for (const row of pushed) {
      const cur = await table.get(row.id);
      if (cur && needsSync(cur) && syncUpdatedAt(cur) === syncUpdatedAt(row)) {
        await table.put({ ...cur, syncState: "synced", lastSyncedAt: syncedAt });
      }
    }
  });
}

// --- pull remote rows ---

async function pullRemoteRows(
  supabase: SupabaseClient,
  workspaceId: string,
  lastPulledMs: number | null,
  syncedAt: number,
): Promise<void> {
  const [localClients, localHeadings, localEntries] = await Promise.all([
    db.clients.count(),
    db.headings.count(),
    db.entries.count(),
  ]);

  // First sync for an (empty) entity pulls everything, ignoring the cursor.
  const clientSince = localClients === 0 ? null : lastPulledMs;
  const headingSince = localHeadings === 0 ? null : lastPulledMs;
  const entrySince = localEntries === 0 ? null : lastPulledMs;

  const [remoteClients, remoteHeadings, remoteEntries, remoteTombstones] = await Promise.all([
    fetchRows<ClientRow>(supabase, "earnline_clients", workspaceId, "updated_at", clientSince),
    fetchRows<HeadingRow>(supabase, "earnline_headings", workspaceId, "updated_at", headingSince),
    fetchRows<EntryRow>(supabase, "earnline_entries", workspaceId, "updated_at", entrySince),
    fetchRows<TombstoneRow>(supabase, "earnline_tombstones", workspaceId, "deleted_at", lastPulledMs),
  ]);

  await db.transaction("rw", db.clients, db.headings, db.entries, async () => {
    const clientsById = new Map((await db.clients.toArray()).map((c) => [c.id, c]));
    for (const row of remoteClients) {
      const remoteUpdatedAt = parseTimestamp(row.updated_at);
      const local = clientsById.get(row.id);
      if (local) {
        if (!shouldApplyRemote(remoteUpdatedAt, syncUpdatedAt(local), local.syncState)) continue;
        const merged: Client = {
          ...local,
          name: row.name,
          colorHex: row.color_hex,
          sortIndex: row.sort_index,
          createdAt: parseTimestamp(row.created_at),
          updatedAt: remoteUpdatedAt,
          syncState: "synced",
          lastSyncedAt: syncedAt,
        };
        await db.clients.put(merged);
        clientsById.set(row.id, merged);
      } else {
        const created = rowToClient(row, syncedAt);
        await db.clients.put(created);
        clientsById.set(row.id, created);
      }
    }

    const headingsById = new Map((await db.headings.toArray()).map((h) => [h.id, h]));
    for (const row of remoteHeadings) {
      const remoteUpdatedAt = parseTimestamp(row.updated_at);
      const local = headingsById.get(row.id);
      if (local) {
        if (!shouldApplyRemote(remoteUpdatedAt, syncUpdatedAt(local), local.syncState)) continue;
        const merged: Heading = {
          ...local,
          title: row.title,
          date: parseDay(row.date),
          sortIndex: row.sort_index,
          createdAt: parseTimestamp(row.created_at),
          updatedAt: remoteUpdatedAt,
          syncState: "synced",
          lastSyncedAt: syncedAt,
        };
        await db.headings.put(merged);
        headingsById.set(row.id, merged);
      } else {
        const created = rowToHeading(row, syncedAt);
        await db.headings.put(created);
        headingsById.set(row.id, created);
      }
    }

    const entriesById = new Map((await db.entries.toArray()).map((e) => [e.id, e]));
    for (const row of remoteEntries) {
      if (!clientsById.has(row.client_id)) continue; // orphan — owner not present
      const remoteUpdatedAt = parseTimestamp(row.updated_at);
      const local = entriesById.get(row.id);
      if (local) {
        if (!shouldApplyRemote(remoteUpdatedAt, syncUpdatedAt(local), local.syncState)) continue;
        const merged: Entry = {
          ...local,
          clientId: row.client_id,
          amountCents: centsFromWire(row.amount),
          currencyCode: row.currency_code,
          project: row.project,
          task: row.task,
          date: parseDay(row.date),
          holdUntil: row.hold_until != null ? parseDay(row.hold_until) : null,
          status: statusFromSyncRawValue(row.status),
          sortIndex: row.sort_index,
          createdAt: parseTimestamp(row.created_at),
          updatedAt: remoteUpdatedAt,
          syncState: "synced",
          lastSyncedAt: syncedAt,
        };
        await db.entries.put(merged);
        entriesById.set(row.id, merged);
      } else {
        const created = rowToEntry(row, syncedAt);
        await db.entries.put(created);
        entriesById.set(row.id, created);
      }
    }

    // Apply remote tombstones last (a local delete still won via pushDeletes).
    for (const row of remoteTombstones) {
      const deletedAt = parseTimestamp(row.deleted_at);
      if (row.entity === "client") {
        const c = clientsById.get(row.record_id);
        if (c && deletedAt >= syncUpdatedAt(c)) {
          await db.clients.delete(c.id);
          const owned = await db.entries.where("clientId").equals(c.id).primaryKeys();
          await db.entries.bulkDelete(owned as string[]);
        }
      } else if (row.entity === "heading") {
        const h = headingsById.get(row.record_id);
        if (h && deletedAt >= syncUpdatedAt(h)) await db.headings.delete(h.id);
      } else if (row.entity === "entry") {
        const e = entriesById.get(row.record_id);
        if (e && deletedAt >= syncUpdatedAt(e)) await db.entries.delete(e.id);
      }
    }
  });
}

function shouldApplyRemote(remoteUpdatedMs: number, localUpdatedMs: number, localState: SyncState): boolean {
  return localState === "synced" || remoteUpdatedMs >= localUpdatedMs;
}

async function fetchRows<T>(
  supabase: SupabaseClient,
  table: string,
  workspaceId: string,
  cursorColumn: string,
  sinceMs: number | null,
): Promise<T[]> {
  const out: T[] = [];
  let from = 0;
  for (;;) {
    let query = supabase.from(table).select("*").eq("workspace_id", workspaceId);
    if (sinceMs != null) query = query.gte(cursorColumn, timestampString(sinceMs));
    const { data, error } = await query.range(from, from + PAGE_SIZE - 1);
    if (error) throw error;
    const batch = (data ?? []) as T[];
    out.push(...batch);
    if (batch.length < PAGE_SIZE) break;
    from += PAGE_SIZE;
  }
  return out;
}

// --- prune (retention hygiene; best-effort) ---

async function pruneRemoteTombstones(
  supabase: SupabaseClient,
  workspaceId: string,
  syncedAt: number,
): Promise<void> {
  const cutoff = syncedAt - TOMBSTONE_RETENTION_MS;
  try {
    await supabase
      .from("earnline_tombstones")
      .delete()
      .eq("workspace_id", workspaceId)
      .lt("deleted_at", timestampString(cutoff));
  } catch {
    // row push/pull already succeeded; pruning can wait for the next sync.
  }
}
