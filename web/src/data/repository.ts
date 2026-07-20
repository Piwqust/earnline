// Mutation layer — mirrors how the iOS views mutate SwiftData: every create/edit
// marks the record dirty (updatedAt = now), and every delete enqueues a tombstone
// (matching SyncDeleteQueue) before removing the row. Deleting a client cascades
// to its entries locally (the iOS relationship cascade / the Postgres FK cascade).

import { getDatabase, type EarnlineDB } from "./db";
import { newUuid, deterministicUuid } from "../domain/deterministicId";
import { nowMs } from "../domain/dateFormat";
import {
  monthReviewId,
  monthReviewMonthStart,
  validateMonthReviewNote,
} from "../domain/monthReview";
import type { Client, Entry, EntryStatus, Heading, MonthReview, SyncEntity } from "../domain/types";

async function enqueueTombstone(
  database: EarnlineDB,
  entity: SyncEntity,
  recordId: string,
  lastSyncedAt?: number | null,
): Promise<void> {
  const now = nowMs();
  await database.tombstones.put({
    id: deterministicUuid(`tombstone:${entity}:${recordId}`),
    entity,
    recordId,
    deletedAt: now,
    createdAt: now,
    lastSyncedAt: lastSyncedAt ?? null,
  });
}

// --- clients ---

export async function createClient(input: {
  name: string;
  colorHex: string;
  sortIndex: number;
}): Promise<Client> {
  const database = getDatabase();
  const now = nowMs();
  const client: Client = {
    id: newUuid(),
    name: input.name,
    colorHex: input.colorHex,
    sortIndex: input.sortIndex,
    createdAt: now,
    updatedAt: now,
    syncState: "dirty",
    lastSyncedAt: null,
  };
  await database.clients.put(client);
  return client;
}

export async function updateClient(
  id: string,
  patch: Partial<Pick<Client, "name" | "colorHex" | "sortIndex">>,
): Promise<void> {
  const database = getDatabase();
  const cur = await database.clients.get(id);
  if (!cur) return;
  await database.clients.put({ ...cur, ...patch, updatedAt: nowMs(), syncState: "dirty" });
}

export async function deleteClient(id: string): Promise<void> {
  const database = getDatabase();
  await database.transaction("rw", database.clients, database.entries, database.tombstones, async () => {
    const client = await database.clients.get(id);
    if (!client) return;
    const entries = await database.entries.where("clientId").equals(id).primaryKeys();
    await database.entries.bulkDelete(entries as string[]);
    await database.clients.delete(id);
    await enqueueTombstone(database, "client", id, client.lastSyncedAt);
  });
}

// --- entries ---

export async function createEntry(input: {
  clientId: string;
  amountCents: number;
  currencyCode: string;
  project: string | null;
  task: string;
  date: number;
  holdUntil: number | null;
  status: EntryStatus;
  sortIndex: number;
}): Promise<Entry> {
  const database = getDatabase();
  const now = nowMs();
  const entry: Entry = {
    id: newUuid(),
    ...input,
    createdAt: now,
    updatedAt: now,
    syncState: "dirty",
    lastSyncedAt: null,
  };
  await database.entries.put(entry);
  return entry;
}

export async function updateEntry(
  id: string,
  patch: Partial<
    Pick<
      Entry,
      "clientId" | "amountCents" | "currencyCode" | "project" | "task" | "date" | "holdUntil" | "status" | "sortIndex"
    >
  >,
): Promise<void> {
  const database = getDatabase();
  const cur = await database.entries.get(id);
  if (!cur) return;
  await database.entries.put({ ...cur, ...patch, updatedAt: nowMs(), syncState: "dirty" });
}

export async function setEntryStatus(id: string, status: EntryStatus): Promise<void> {
  await updateEntry(id, { status });
}

export async function deleteEntry(id: string): Promise<void> {
  const database = getDatabase();
  await database.transaction("rw", database.entries, database.tombstones, async () => {
    const entry = await database.entries.get(id);
    if (!entry) return;
    await database.entries.delete(id);
    await enqueueTombstone(database, "entry", id, entry.lastSyncedAt);
  });
}

// --- headings ---

export async function createHeading(input: {
  title: string;
  date: number;
  sortIndex: number;
}): Promise<Heading> {
  const database = getDatabase();
  const now = nowMs();
  const heading: Heading = {
    id: newUuid(),
    ...input,
    createdAt: now,
    updatedAt: now,
    syncState: "dirty",
    lastSyncedAt: null,
  };
  await database.headings.put(heading);
  return heading;
}

export async function updateHeading(
  id: string,
  patch: Partial<Pick<Heading, "title" | "date" | "sortIndex">>,
): Promise<void> {
  const database = getDatabase();
  const cur = await database.headings.get(id);
  if (!cur) return;
  await database.headings.put({ ...cur, ...patch, updatedAt: nowMs(), syncState: "dirty" });
}

export async function deleteHeading(id: string): Promise<void> {
  const database = getDatabase();
  await database.transaction("rw", database.headings, database.tombstones, async () => {
    const heading = await database.headings.get(id);
    if (!heading) return;
    await database.headings.delete(id);
    await enqueueTombstone(database, "heading", id, heading.lastSyncedAt);
  });
}

// --- month reviews ---

/** Soft-close a calendar month. The row is retained and updates the same
 * deterministic record on every client instead of creating a deletion race. */
export async function closeMonthReview(input: {
  monthContaining: number;
  note: string;
}): Promise<MonthReview> {
  validateMonthReviewNote(input.note);
  const database = getDatabase();
  const monthStart = monthReviewMonthStart(input.monthContaining);
  const id = monthReviewId(monthStart);
  const now = nowMs();
  const current = await database.monthReviews.get(id);
  const review: MonthReview = {
    id,
    monthStart,
    note: input.note,
    closedAt: now,
    createdAt: current?.createdAt ?? now,
    updatedAt: now,
    syncState: "dirty",
    lastSyncedAt: current?.lastSyncedAt ?? null,
  };
  await database.monthReviews.put(review);
  return review;
}

/** Reopening is an upsert with `closedAt = null`; it never creates a tombstone. */
export async function reopenMonthReview(monthContaining: number): Promise<MonthReview | undefined> {
  const database = getDatabase();
  const id = monthReviewId(monthContaining);
  const current = await database.monthReviews.get(id);
  if (!current || current.closedAt == null) return current;
  const reopened: MonthReview = {
    ...current,
    closedAt: null,
    updatedAt: nowMs(),
    syncState: "dirty",
  };
  await database.monthReviews.put(reopened);
  return reopened;
}

// --- counts (Settings: pending sync) ---

export async function pendingSyncCount(): Promise<number> {
  const database = getDatabase();
  const [clients, entries, headings, monthReviews, tombstones] = await Promise.all([
    database.clients.where("syncState").notEqual("synced").count(),
    database.entries.where("syncState").notEqual("synced").count(),
    database.headings.where("syncState").notEqual("synced").count(),
    database.monthReviews.where("syncState").notEqual("synced").count(),
    database.tombstones.count(),
  ]);
  return clients + entries + headings + monthReviews + tombstones;
}
