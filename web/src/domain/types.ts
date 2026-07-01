// Core domain types — ported from the iOS SwiftData models (Models/*).
//
// Representation choices for the web port:
//  - Monetary amounts are stored as **integer cents** (exact for 2dp values up
//    to 1e9; matches the numeric(14,2) Postgres column).
//  - Dates are stored as **epoch milliseconds**. "Day-valued" fields (entry.date,
//    holdUntil, heading.date) are UTC-midnight of the chosen calendar day so they
//    round-trip the wire `yyyy-MM-dd` cleanly; timestamps are real instants.

export type EntryStatus = "paid" | "inProgress" | "canceled";

export const STATUS_ORDER: EntryStatus[] = ["paid", "inProgress", "canceled"];

/** Unknown/legacy raw values (e.g. the old "logged") fall back to `paid`. */
export function statusFromSyncRawValue(raw: string): EntryStatus {
  if (raw === "logged") return "paid";
  return raw === "paid" || raw === "inProgress" || raw === "canceled" ? raw : "paid";
}

export function isIncludedInEarnedTotals(status: EntryStatus): boolean {
  return status !== "canceled";
}

export function statusTitle(status: EntryStatus): string {
  switch (status) {
    case "paid":
      return "Paid";
    case "inProgress":
      return "In progress";
    case "canceled":
      return "Canceled";
  }
}

/** Cycling order: paid → in progress → canceled → paid. */
export function nextStatus(status: EntryStatus): EntryStatus {
  switch (status) {
    case "paid":
      return "inProgress";
    case "inProgress":
      return "canceled";
    case "canceled":
      return "paid";
  }
}

export type SyncState = "dirty" | "synced" | "failed";
export type SyncEntity = "client" | "entry" | "heading";

export interface Client {
  id: string;
  name: string;
  colorHex: string;
  sortIndex: number;
  createdAt: number;
  updatedAt?: number | null;
  syncState: SyncState;
  lastSyncedAt?: number | null;
}

export interface Entry {
  id: string;
  clientId: string;
  amountCents: number;
  currencyCode: string;
  project?: string | null;
  task: string;
  date: number; // UTC-midnight day, epoch ms
  holdUntil?: number | null; // UTC-midnight day, epoch ms
  status: EntryStatus;
  sortIndex: number;
  createdAt: number;
  updatedAt?: number | null;
  syncState: SyncState;
  lastSyncedAt?: number | null;
}

export interface Heading {
  id: string;
  title: string;
  date: number; // UTC-midnight day, epoch ms
  sortIndex: number;
  createdAt: number;
  updatedAt?: number | null;
  syncState: SyncState;
  lastSyncedAt?: number | null;
}

export interface Tombstone {
  id: string;
  entity: SyncEntity;
  recordId: string;
  deletedAt: number;
  createdAt: number;
}

/** Structured result of understanding a freeform income line (mirrors ParsedLine). */
export interface ParsedLine {
  amount?: number; // dollars (not cents) — the composer converts to cents on commit
  currencyCode: string;
  project?: string;
  task: string;
  holdUntil?: number; // UTC-midnight day, epoch ms
  status?: EntryStatus;
}

/** Enough information present to commit a real line. */
export function isCommittable(p: ParsedLine): boolean {
  return p.amount != null && (p.task !== "" || p.project != null);
}

// --- sync metadata helpers (mirror the SyncState.swift extensions) ---

export function syncUpdatedAt(r: { updatedAt?: number | null; createdAt: number }): number {
  return r.updatedAt ?? r.createdAt;
}

export function needsSync(r: { syncState: SyncState }): boolean {
  return r.syncState !== "synced";
}
