// Connection-scoped local-first storage. Every validated remote workspace gets
// its own IndexedDB database, so changing a proxy/capability can never merge
// one ledger with another. The legacy `earnline` database remains the initial
// scope and is copied once when an existing install is paired for the first
// time.

import Dexie, { type Table } from "dexie";
import { useSyncExternalStore } from "react";
import type { Client, Entry, Heading, Tombstone } from "../domain/types";

export interface SyncMetadata {
  id: "sync";
  rowCursorMs: number | null;
  lastSyncAt: number | null;
}

export interface SyncLease {
  id: "sync";
  token: string;
  expiresAt: number;
}

export interface RecoveryEnvelope {
  format: "earnline-web-backup";
  version: 1;
  exportedAt: string;
  scope: string;
  clients: Client[];
  entries: Entry[];
  headings: Heading[];
  tombstones: Tombstone[];
}

const LEGACY_DATABASE_NAME = "earnline";
const SETTINGS_KEY = "earnline.settings";

function safeScope(raw: unknown): string {
  if (typeof raw !== "string") return "local";
  const clean = raw.trim().toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 64);
  return clean || "local";
}

function initialScope(): string {
  try {
    const parsed = JSON.parse(localStorage.getItem(SETTINGS_KEY) ?? "{}") as { connectionScope?: unknown };
    return safeScope(parsed.connectionScope);
  } catch {
    return "local";
  }
}

function databaseName(scope: string): string {
  return scope === "local" ? LEGACY_DATABASE_NAME : `earnline-${safeScope(scope)}`;
}

export class EarnlineDB extends Dexie {
  clients!: Table<Client, string>;
  entries!: Table<Entry, string>;
  headings!: Table<Heading, string>;
  tombstones!: Table<Tombstone, string>;
  syncMetadata!: Table<SyncMetadata, "sync">;
  syncLeases!: Table<SyncLease, "sync">;

  readonly scope: string;

  constructor(scope = "local") {
    super(databaseName(scope));
    this.scope = safeScope(scope);
    this.version(1).stores({
      clients: "id, sortIndex, syncState, updatedAt",
      entries: "id, clientId, date, sortIndex, syncState, updatedAt",
      headings: "id, date, sortIndex, syncState, updatedAt",
      tombstones: "id, entity, recordId, deletedAt",
    });
    this.version(2).stores({
      clients: "id, sortIndex, syncState, updatedAt",
      entries: "id, clientId, date, sortIndex, syncState, updatedAt",
      headings: "id, date, sortIndex, syncState, updatedAt",
      tombstones: "id, entity, recordId, deletedAt",
      syncMetadata: "id",
    });
    this.version(3).stores({
      clients: "id, sortIndex, syncState, updatedAt",
      entries: "id, clientId, date, sortIndex, syncState, updatedAt",
      headings: "id, date, sortIndex, syncState, updatedAt",
      tombstones: "id, entity, recordId, deletedAt",
      syncMetadata: "id",
      syncLeases: "id, expiresAt",
    });
  }
}

export let db = new EarnlineDB(initialScope());

let generation = 0;
let activationRequest = 0;
let activationQueue: Promise<void> = Promise.resolve();
const databaseListeners = new Set<() => void>();

export function getDatabase(): EarnlineDB {
  return db;
}

export function getDatabaseGeneration(): number {
  return generation;
}

export function subscribeDatabase(listener: () => void): () => void {
  databaseListeners.add(listener);
  return () => databaseListeners.delete(listener);
}

export function useDatabaseGeneration(): number {
  return useSyncExternalStore(subscribeDatabase, getDatabaseGeneration, getDatabaseGeneration);
}

function emitDatabaseChanged(): void {
  generation += 1;
  for (const listener of databaseListeners) listener();
}

async function isEmpty(database: EarnlineDB): Promise<boolean> {
  const [clients, entries, headings, tombstones] = await Promise.all([
    database.clients.count(),
    database.entries.count(),
    database.headings.count(),
    database.tombstones.count(),
  ]);
  return clients + entries + headings + tombstones === 0;
}

async function copyDatabase(source: EarnlineDB, target: EarnlineDB): Promise<void> {
  const [clients, entries, headings, tombstones, metadata] = await Promise.all([
    source.clients.toArray(),
    source.entries.toArray(),
    source.headings.toArray(),
    source.tombstones.toArray(),
    source.syncMetadata.get("sync"),
  ]);
  await target.transaction(
    "rw",
    target.clients,
    target.entries,
    target.headings,
    target.tombstones,
    target.syncMetadata,
    async () => {
      await Promise.all([
        target.clients.bulkPut(clients),
        target.entries.bulkPut(entries),
        target.headings.bulkPut(headings),
        target.tombstones.bulkPut(tombstones),
      ]);
      if (metadata) await target.syncMetadata.put(metadata);
    },
  );
}

/**
 * Switch the live module binding to an isolated database. Existing legacy data
 * is copied only when pairing an otherwise empty target for the first time.
 */
export async function activateDatabase(
  scope: string,
  options: { migrateLegacy?: boolean } = {},
): Promise<EarnlineDB> {
  const normalized = safeScope(scope);
  const request = ++activationRequest;
  let result = db;
  const operation = activationQueue.then(async () => {
    // A newer connection request supersedes this one even when it points back
    // to the currently active scope.
    if (request !== activationRequest || db.scope === normalized) {
      result = db;
      return;
    }

    const previous = db;
    const next = new EarnlineDB(normalized);
    await next.open();
    if (request !== activationRequest) {
      next.close();
      result = db;
      return;
    }
    if (options.migrateLegacy === true && previous.scope === "local" && (await isEmpty(next))) {
      await copyDatabase(previous, next);
    }
    if (request !== activationRequest) {
      next.close();
      result = db;
      return;
    }
    db = next;
    result = next;
    emitDatabaseChanged();
    previous.close();
  });
  activationQueue = operation.then(() => undefined, () => undefined);
  await operation;
  return result;
}

export async function requestPersistentStorage(): Promise<boolean | null> {
  if (!navigator.storage?.persist) return null;
  try {
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}

export async function exportDatabase(database: EarnlineDB = db): Promise<RecoveryEnvelope> {
  const [clients, entries, headings, tombstones] = await Promise.all([
    database.clients.toArray(),
    database.entries.toArray(),
    database.headings.toArray(),
    database.tombstones.toArray(),
  ]);
  return {
    format: "earnline-web-backup",
    version: 1,
    exportedAt: new Date().toISOString(),
    scope: database.scope,
    clients,
    entries,
    headings,
    tombstones,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function decodeRecoveryEnvelope(value: unknown): RecoveryEnvelope {
  if (!isRecord(value) || value.format !== "earnline-web-backup" || value.version !== 1) {
    throw new Error("This file is not a supported Earnline backup.");
  }
  for (const key of ["clients", "entries", "headings", "tombstones"] as const) {
    if (!Array.isArray(value[key])) throw new Error(`Backup field ${key} is missing.`);
  }
  return value as unknown as RecoveryEnvelope;
}

/** Restore is additive by id and marks restored rows dirty so they are pushed. */
export async function importDatabase(
  raw: unknown,
  database: EarnlineDB = db,
): Promise<{ clients: number; entries: number; headings: number; tombstones: number }> {
  const backup = decodeRecoveryEnvelope(raw);
  const now = Date.now();
  const clients = backup.clients.map((row) => ({ ...row, syncState: "dirty" as const, updatedAt: now }));
  const headings = backup.headings.map((row) => ({ ...row, syncState: "dirty" as const, updatedAt: now }));
  const entries = backup.entries.map((row) => ({ ...row, syncState: "dirty" as const, updatedAt: now }));
  await database.transaction(
    "rw",
    database.clients,
    database.entries,
    database.headings,
    database.tombstones,
    async () => {
      await database.clients.bulkPut(clients);
      await database.headings.bulkPut(headings);
      await database.entries.bulkPut(entries);
      await database.tombstones.bulkPut(backup.tombstones);
    },
  );
  return {
    clients: clients.length,
    entries: entries.length,
    headings: headings.length,
    tombstones: backup.tombstones.length,
  };
}
