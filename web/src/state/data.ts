// Reactive reads from the local store — the web analog of SwiftData @Query.
import { useLiveQuery } from "dexie-react-hooks";
import { db } from "../data/db";
import type { Client, Entry, Heading } from "../domain/types";

const EMPTY: never[] = [];

export function useClients(): Client[] {
  return useLiveQuery(() => db.clients.orderBy("sortIndex").toArray(), [], EMPTY as Client[]);
}

export function useEntries(): Entry[] {
  return useLiveQuery(() => db.entries.toArray(), [], EMPTY as Entry[]);
}

export function useHeadings(): Heading[] {
  return useLiveQuery(() => db.headings.orderBy("sortIndex").toArray(), [], EMPTY as Heading[]);
}

export function useClient(id: string | undefined): Client | undefined {
  return useLiveQuery(() => (id ? db.clients.get(id) : undefined), [id], undefined);
}
