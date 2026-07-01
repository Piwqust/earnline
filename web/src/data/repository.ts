// Mutation layer — mirrors how the iOS views mutate SwiftData: every create/edit
// marks the record dirty (updatedAt = now), and every delete enqueues a tombstone
// (matching SyncDeleteQueue) before removing the row. Deleting a client cascades
// to its entries locally (the iOS relationship cascade / the Postgres FK cascade).

import { db } from "./db";
import { newUuid, deterministicUuid } from "../domain/deterministicId";
import { nowMs } from "../domain/dateFormat";
import type { Client, Entry, EntryStatus, Heading, SyncEntity } from "../domain/types";

async function enqueueTombstone(entity: SyncEntity, recordId: string): Promise<void> {
  const now = nowMs();
  await db.tombstones.put({
    id: deterministicUuid(`tombstone:${entity}:${recordId}`),
    entity,
    recordId,
    deletedAt: now,
    createdAt: now,
  });
}

// --- clients ---

export async function createClient(input: {
  name: string;
  colorHex: string;
  sortIndex: number;
}): Promise<Client> {
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
  await db.clients.put(client);
  return client;
}

export async function updateClient(
  id: string,
  patch: Partial<Pick<Client, "name" | "colorHex" | "sortIndex">>,
): Promise<void> {
  const cur = await db.clients.get(id);
  if (!cur) return;
  await db.clients.put({ ...cur, ...patch, updatedAt: nowMs(), syncState: "dirty" });
}

export async function deleteClient(id: string): Promise<void> {
  await db.transaction("rw", db.clients, db.entries, db.tombstones, async () => {
    const entries = await db.entries.where("clientId").equals(id).primaryKeys();
    await db.entries.bulkDelete(entries as string[]);
    await db.clients.delete(id);
    await enqueueTombstone("client", id);
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
  const now = nowMs();
  const entry: Entry = {
    id: newUuid(),
    ...input,
    createdAt: now,
    updatedAt: now,
    syncState: "dirty",
    lastSyncedAt: null,
  };
  await db.entries.put(entry);
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
  const cur = await db.entries.get(id);
  if (!cur) return;
  await db.entries.put({ ...cur, ...patch, updatedAt: nowMs(), syncState: "dirty" });
}

export async function setEntryStatus(id: string, status: EntryStatus): Promise<void> {
  await updateEntry(id, { status });
}

export async function deleteEntry(id: string): Promise<void> {
  await db.transaction("rw", db.entries, db.tombstones, async () => {
    await db.entries.delete(id);
    await enqueueTombstone("entry", id);
  });
}

// --- headings ---

export async function createHeading(input: {
  title: string;
  date: number;
  sortIndex: number;
}): Promise<Heading> {
  const now = nowMs();
  const heading: Heading = {
    id: newUuid(),
    ...input,
    createdAt: now,
    updatedAt: now,
    syncState: "dirty",
    lastSyncedAt: null,
  };
  await db.headings.put(heading);
  return heading;
}

export async function updateHeading(
  id: string,
  patch: Partial<Pick<Heading, "title" | "date" | "sortIndex">>,
): Promise<void> {
  const cur = await db.headings.get(id);
  if (!cur) return;
  await db.headings.put({ ...cur, ...patch, updatedAt: nowMs(), syncState: "dirty" });
}

export async function deleteHeading(id: string): Promise<void> {
  await db.transaction("rw", db.headings, db.tombstones, async () => {
    await db.headings.delete(id);
    await enqueueTombstone("heading", id);
  });
}

// --- counts (Settings: pending sync) ---

export async function pendingSyncCount(): Promise<number> {
  const [clients, entries, headings, tombstones] = await Promise.all([
    db.clients.where("syncState").notEqual("synced").count(),
    db.entries.where("syncState").notEqual("synced").count(),
    db.headings.where("syncState").notEqual("synced").count(),
    db.tombstones.count(),
  ]);
  return clients + entries + headings + tombstones;
}
