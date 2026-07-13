// Wire DTOs + strict row mappers. Malformed remote rows fail the pass instead
// of being rewritten with `Date.now()`/today; therefore the cursor never moves
// past data the client did not actually understand.

import type { Client, Entry, EntryStatus, Heading, SyncEntity, Tombstone } from "../domain/types";
import { syncUpdatedAt } from "../domain/types";
import { centsFromWire, centsToWireString } from "../domain/money";
import { dayMsFromInputValue, inputValueFromDayMs } from "../domain/dateFormat";

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
  status: EntryStatus;
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
  entity: SyncEntity;
  record_id: string;
  deleted_at: string;
  created_at: string;
}

export interface WorkspaceProfileRow {
  workspace_id: string;
  base_currency_code: string;
  secondary_currency_code: string;
  exchange_rate: string | number;
  updated_at: string;
}

export interface WorkspaceProfilePayload {
  workspace_id: string;
  base_currency_code: string;
  secondary_currency_code: string;
  exchange_rate: string;
}

export class RemoteDecodeError extends Error {
  constructor(message: string) {
    super(`Invalid sync response: ${message}`);
    this.name = "RemoteDecodeError";
  }
}

function object(value: unknown, context: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new RemoteDecodeError(`${context} is not an object.`);
  }
  return value as Record<string, unknown>;
}

function rows(value: unknown, context: string): Record<string, unknown>[] {
  if (!Array.isArray(value)) throw new RemoteDecodeError(`${context} is not an array.`);
  return value.map((row, index) => object(row, `${context}[${index}]`));
}

function string(row: Record<string, unknown>, key: string, context: string, allowEmpty = false): string {
  const value = row[key];
  if (typeof value !== "string" || (!allowEmpty && value.trim() === "")) {
    throw new RemoteDecodeError(`${context}.${key} is not a valid string.`);
  }
  return value;
}

function nullableString(row: Record<string, unknown>, key: string, context: string): string | null {
  const value = row[key];
  if (value === null) return null;
  if (typeof value !== "string") throw new RemoteDecodeError(`${context}.${key} is not nullable text.`);
  return value;
}

function integer(row: Record<string, unknown>, key: string, context: string): number {
  const value = row[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new RemoteDecodeError(`${context}.${key} is not an integer.`);
  }
  return value;
}

function timestamp(row: Record<string, unknown>, key: string, context: string): string {
  const value = string(row, key, context);
  if (parseTimestamp(value) == null) throw new RemoteDecodeError(`${context}.${key} is not an ISO timestamp.`);
  return value;
}

function day(row: Record<string, unknown>, key: string, context: string): string {
  const value = string(row, key, context);
  if (parseDay(value) == null) throw new RemoteDecodeError(`${context}.${key} is not yyyy-MM-dd.`);
  return value;
}

function amount(row: Record<string, unknown>, key: string, context: string): string | number {
  const value = row[key];
  const validText = typeof value === "string" && /^-?\d+(?:\.\d{1,2})?$/.test(value);
  const validNumber = typeof value === "number" && Number.isFinite(value);
  if ((!validText && !validNumber) || !Number.isSafeInteger(centsFromWire(value as string | number))) {
    throw new RemoteDecodeError(`${context}.${key} is not an exact 2-decimal amount.`);
  }
  return value;
}

function status(row: Record<string, unknown>, context: string): EntryStatus {
  const value = string(row, "status", context);
  if (value === "logged") return "paid";
  if (value !== "paid" && value !== "inProgress" && value !== "canceled") {
    throw new RemoteDecodeError(`${context}.status is unsupported.`);
  }
  return value;
}

function entity(row: Record<string, unknown>, context: string): SyncEntity {
  const value = string(row, "entity", context);
  if (value !== "client" && value !== "entry" && value !== "heading") {
    throw new RemoteDecodeError(`${context}.entity is unsupported.`);
  }
  return value;
}

export function timestampString(ms: number): string {
  if (!Number.isFinite(ms)) throw new Error("Cannot encode an invalid timestamp.");
  return new Date(ms).toISOString();
}

export function parseTimestamp(value: string): number | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(value)) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

export function dayString(ms: number): string {
  return inputValueFromDayMs(ms);
}

export function parseDay(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const parsed = dayMsFromInputValue(value);
  return parsed != null && inputValueFromDayMs(parsed) === value ? parsed : null;
}

export function decodeClientRows(value: unknown): ClientRow[] {
  return rows(value, "clients").map((row, index) => {
    const c = `clients[${index}]`;
    return {
      id: string(row, "id", c), workspace_id: string(row, "workspace_id", c),
      name: string(row, "name", c), color_hex: string(row, "color_hex", c),
      sort_index: integer(row, "sort_index", c), created_at: timestamp(row, "created_at", c),
      updated_at: timestamp(row, "updated_at", c),
    };
  });
}

export function decodeEntryRows(value: unknown): EntryRow[] {
  return rows(value, "entries").map((row, index) => {
    const c = `entries[${index}]`;
    const hold = nullableString(row, "hold_until", c);
    if (hold != null && parseDay(hold) == null) throw new RemoteDecodeError(`${c}.hold_until is not yyyy-MM-dd.`);
    return {
      id: string(row, "id", c), workspace_id: string(row, "workspace_id", c),
      client_id: string(row, "client_id", c), amount: amount(row, "amount", c),
      currency_code: string(row, "currency_code", c), project: nullableString(row, "project", c),
      task: string(row, "task", c, true), date: day(row, "date", c), hold_until: hold,
      status: status(row, c), sort_index: integer(row, "sort_index", c),
      created_at: timestamp(row, "created_at", c), updated_at: timestamp(row, "updated_at", c),
    };
  });
}

export function decodeHeadingRows(value: unknown): HeadingRow[] {
  return rows(value, "headings").map((row, index) => {
    const c = `headings[${index}]`;
    return {
      id: string(row, "id", c), workspace_id: string(row, "workspace_id", c),
      title: string(row, "title", c), date: day(row, "date", c),
      sort_index: integer(row, "sort_index", c), created_at: timestamp(row, "created_at", c),
      updated_at: timestamp(row, "updated_at", c),
    };
  });
}

export function decodeTombstoneRows(value: unknown): TombstoneRow[] {
  return rows(value, "tombstones").map((row, index) => {
    const c = `tombstones[${index}]`;
    return {
      id: string(row, "id", c), workspace_id: string(row, "workspace_id", c), entity: entity(row, c),
      record_id: string(row, "record_id", c), deleted_at: timestamp(row, "deleted_at", c),
      created_at: timestamp(row, "created_at", c),
    };
  });
}

export function decodeWorkspaceProfile(value: unknown): WorkspaceProfileRow {
  const row = object(value, "profile");
  const rawRate = row.exchange_rate;
  const rate = typeof rawRate === "number" && Number.isFinite(rawRate) ? rawRate
    : typeof rawRate === "string" && /^\d+(?:\.\d+)?$/.test(rawRate) ? rawRate : null;
  if (rate == null || !(Number(rate) > 0)) throw new RemoteDecodeError("profile.exchange_rate must be positive.");
  const base = string(row, "base_currency_code", "profile").toUpperCase();
  const secondary = string(row, "secondary_currency_code", "profile").toUpperCase();
  if (base === secondary) throw new RemoteDecodeError("profile currency pair is invalid.");
  return {
    workspace_id: string(row, "workspace_id", "profile"), base_currency_code: base,
    secondary_currency_code: secondary, exchange_rate: rate,
    updated_at: timestamp(row, "updated_at", "profile"),
  };
}

export function clientToRow(c: Client, workspaceId: string): ClientRow {
  return { id: c.id, workspace_id: workspaceId, name: c.name, color_hex: c.colorHex, sort_index: c.sortIndex,
    created_at: timestampString(c.createdAt), updated_at: timestampString(syncUpdatedAt(c)) };
}

export function entryToRow(e: Entry, workspaceId: string): EntryRow {
  return { id: e.id, workspace_id: workspaceId, client_id: e.clientId, amount: centsToWireString(e.amountCents),
    currency_code: e.currencyCode, project: e.project ?? null, task: e.task, date: dayString(e.date),
    hold_until: e.holdUntil != null ? dayString(e.holdUntil) : null, status: e.status, sort_index: e.sortIndex,
    created_at: timestampString(e.createdAt), updated_at: timestampString(syncUpdatedAt(e)) };
}

export function headingToRow(h: Heading, workspaceId: string): HeadingRow {
  return { id: h.id, workspace_id: workspaceId, title: h.title, date: dayString(h.date), sort_index: h.sortIndex,
    created_at: timestampString(h.createdAt), updated_at: timestampString(syncUpdatedAt(h)) };
}

export function tombstoneToRow(t: Tombstone, workspaceId: string): TombstoneRow {
  return { id: t.id, workspace_id: workspaceId, entity: t.entity, record_id: t.recordId,
    deleted_at: timestampString(t.deletedAt), created_at: timestampString(t.createdAt) };
}

function requiredTimestamp(value: string, context: string): number {
  const parsed = parseTimestamp(value);
  if (parsed == null) throw new RemoteDecodeError(`${context} timestamp is invalid.`);
  return parsed;
}

function requiredDay(value: string, context: string): number {
  const parsed = parseDay(value);
  if (parsed == null) throw new RemoteDecodeError(`${context} day is invalid.`);
  return parsed;
}

export function rowToClient(row: ClientRow, syncedAt: number): Client {
  const updatedAt = requiredTimestamp(row.updated_at, "client.updated_at");
  return { id: row.id, name: row.name, colorHex: row.color_hex, sortIndex: row.sort_index,
    createdAt: requiredTimestamp(row.created_at, "client.created_at"), updatedAt, syncState: "synced",
    lastSyncedAt: updatedAt || syncedAt };
}

export function rowToEntry(row: EntryRow, syncedAt: number): Entry {
  const updatedAt = requiredTimestamp(row.updated_at, "entry.updated_at");
  return { id: row.id, clientId: row.client_id, amountCents: centsFromWire(row.amount),
    currencyCode: row.currency_code, project: row.project, task: row.task, date: requiredDay(row.date, "entry.date"),
    holdUntil: row.hold_until != null ? requiredDay(row.hold_until, "entry.hold_until") : null,
    status: row.status, sortIndex: row.sort_index, createdAt: requiredTimestamp(row.created_at, "entry.created_at"),
    updatedAt, syncState: "synced", lastSyncedAt: updatedAt || syncedAt };
}

export function rowToHeading(row: HeadingRow, syncedAt: number): Heading {
  const updatedAt = requiredTimestamp(row.updated_at, "heading.updated_at");
  return { id: row.id, title: row.title, date: requiredDay(row.date, "heading.date"), sortIndex: row.sort_index,
    createdAt: requiredTimestamp(row.created_at, "heading.created_at"), updatedAt, syncState: "synced",
    lastSyncedAt: updatedAt || syncedAt };
}

export function tableFor(entity: SyncEntity): Exclude<import("./remoteClient").RowTable, "earnline_tombstones"> {
  switch (entity) {
    case "client": return "earnline_clients";
    case "entry": return "earnline_entries";
    case "heading": return "earnline_headings";
  }
}
