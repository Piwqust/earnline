// Local-first store (IndexedDB via Dexie) — the web analog of the iOS SwiftData
// store. Holds the same four entities plus sync metadata; UI reads it reactively
// with useLiveQuery (the analog of SwiftData @Query).

import Dexie, { type Table } from "dexie";
import type { Client, Entry, Heading, Tombstone } from "../domain/types";

export class EarnlineDB extends Dexie {
  clients!: Table<Client, string>;
  entries!: Table<Entry, string>;
  headings!: Table<Heading, string>;
  tombstones!: Table<Tombstone, string>;

  constructor() {
    super("earnline");
    this.version(1).stores({
      clients: "id, sortIndex, syncState, updatedAt",
      entries: "id, clientId, date, sortIndex, syncState, updatedAt",
      headings: "id, date, sortIndex, syncState, updatedAt",
      tombstones: "id, entity, recordId, deletedAt",
    });
  }
}

export const db = new EarnlineDB();
