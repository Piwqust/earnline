// Wire DTOs + row⇄model mappers — exact parity with iOS Sync/RemoteRecords.swift.
// Column names are snake_case; amounts are 2dp strings; days are yyyy-MM-dd (UTC);
// timestamps are ISO-8601 with fractional seconds.

import type { Client, Entry, Heading, SyncEntity, Tombstone } from "../domain/types";
import { statusFromSyncRawValue, syncUpdatedAt } from "../domain/types";
import { centsFromWire, centsToWireString } from "../domain/money";
import { dayMsFromInputValue, inputValueFromDayMs, todayDayMs } from "../domain/dateFormat";

export interface ClientRow {
  id: string;
  workspace_id: string;
  name: string;
  color_hex: string;
  sort_index: number;
  created_at: string;
  updated_at: string;
}

export interface EntryRow {
  id: string;
  workspace_id: string;
  client_id: string;
  amount: string | number;
  currency_code: string;
  project: string | null;
  task: string;
  date: string;
  hold_until: string | null;
  status: string;
  sort_index: number;
  created_at: string;
  updated_at: string;
}

export interface HeadingRow {
  id: string;
  workspace_id: string;
  title: string;
  date: string;
  sort_index: number;
  created_at: string;
  updated_at: string;
}

export interface TombstoneRow {
  id: string;
  workspace_id: string;
  entity: string;
  record_id: string;
  deleted_at: string;
  created_at: string;
}

// --- SyncDateCodec ---

export function timestampString(ms: number): string {
  return new Date(ms).toISOString(); // ISO-8601 with milliseconds + Z
}

export function parseTimestamp(value: string): number {
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : Date.now();
}

export function dayString(ms: number): string {
  return inputValueFromDayMs(ms);
}

export function parseDay(value: string): number {
  return dayMsFromInputValue(value) ?? todayDayMs();
}

// --- model → row ---

export function clientToRow(c: Client, workspaceId: string): ClientRow {
  return {
    id: c.id,
    workspace_id: workspaceId,
    name: c.name,
    color_hex: c.colorHex,
    sort_index: c.sortIndex,
    created_at: timestampString(c.createdAt),
    updated_at: timestampString(syncUpdatedAt(c)),
  };
}

export function entryToRow(e: Entry, workspaceId: string): EntryRow {
  return {
    id: e.id,
    workspace_id: workspaceId,
    client_id: e.clientId,
    amount: centsToWireString(e.amountCents),
    currency_code: e.currencyCode,
    project: e.project ?? null,
    task: e.task,
    date: dayString(e.date),
    hold_until: e.holdUntil != null ? dayString(e.holdUntil) : null,
    status: e.status,
    sort_index: e.sortIndex,
    created_at: timestampString(e.createdAt),
    updated_at: timestampString(syncUpdatedAt(e)),
  };
}

export function headingToRow(h: Heading, workspaceId: string): HeadingRow {
  return {
    id: h.id,
    workspace_id: workspaceId,
    title: h.title,
    date: dayString(h.date),
    sort_index: h.sortIndex,
    created_at: timestampString(h.createdAt),
    updated_at: timestampString(syncUpdatedAt(h)),
  };
}

export function tombstoneToRow(t: Tombstone, workspaceId: string): TombstoneRow {
  return {
    id: t.id,
    workspace_id: workspaceId,
    entity: t.entity,
    record_id: t.recordId,
    deleted_at: timestampString(t.deletedAt),
    created_at: timestampString(t.createdAt),
  };
}

// --- row → model (always marked synced) ---

export function rowToClient(row: ClientRow, syncedAt: number): Client {
  return {
    id: row.id,
    name: row.name,
    colorHex: row.color_hex,
    sortIndex: row.sort_index,
    createdAt: parseTimestamp(row.created_at),
    updatedAt: parseTimestamp(row.updated_at),
    syncState: "synced",
    lastSyncedAt: syncedAt,
  };
}

export function rowToEntry(row: EntryRow, syncedAt: number): Entry {
  return {
    id: row.id,
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
    updatedAt: parseTimestamp(row.updated_at),
    syncState: "synced",
    lastSyncedAt: syncedAt,
  };
}

export function rowToHeading(row: HeadingRow, syncedAt: number): Heading {
  return {
    id: row.id,
    title: row.title,
    date: parseDay(row.date),
    sortIndex: row.sort_index,
    createdAt: parseTimestamp(row.created_at),
    updatedAt: parseTimestamp(row.updated_at),
    syncState: "synced",
    lastSyncedAt: syncedAt,
  };
}

export const TOMBSTONE_TABLE = "earnline_tombstones";

export function tableFor(entity: SyncEntity): string {
  switch (entity) {
    case "client":
      return "earnline_clients";
    case "entry":
      return "earnline_entries";
    case "heading":
      return "earnline_headings";
  }
}
