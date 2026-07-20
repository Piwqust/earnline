// Reactive reads from the local store — the web analog of SwiftData @Query.
import { useLiveQuery } from "dexie-react-hooks";
import { getDatabase, useDatabaseGeneration } from "../data/db";
import type { Client, Entry, Heading, MonthReview } from "../domain/types";

const EMPTY_CLIENTS: Client[] = [];
const EMPTY_ENTRIES: Entry[] = [];
const EMPTY_HEADINGS: Heading[] = [];
const EMPTY_MONTH_REVIEWS: MonthReview[] = [];

export function useClients(): Client[] {
  const generation = useDatabaseGeneration();
  return useLiveQuery(() => getDatabase().clients.orderBy("sortIndex").toArray(), [generation], EMPTY_CLIENTS);
}

export function useEntries(): Entry[] {
  const generation = useDatabaseGeneration();
  return useLiveQuery(() => getDatabase().entries.toArray(), [generation], EMPTY_ENTRIES);
}

export function useHeadings(): Heading[] {
  const generation = useDatabaseGeneration();
  return useLiveQuery(() => getDatabase().headings.orderBy("sortIndex").toArray(), [generation], EMPTY_HEADINGS);
}

export function useMonthReviews(): MonthReview[] {
  const generation = useDatabaseGeneration();
  return useLiveQuery(
    () => getDatabase().monthReviews.orderBy("monthStart").toArray(),
    [generation],
    EMPTY_MONTH_REVIEWS,
  );
}

export function useClient(id: string | undefined): Client | undefined {
  const generation = useDatabaseGeneration();
  return useLiveQuery(() => (id ? getDatabase().clients.get(id) : undefined), [generation, id], undefined);
}

/** Distinguish a genuinely empty ledger from Dexie's first unresolved frame. */
export function useDataReady(): boolean {
  const generation = useDatabaseGeneration();
  return (
    useLiveQuery(
      async () => {
        const database = getDatabase();
        await Promise.all([
          database.clients.count(),
          database.entries.count(),
          database.headings.count(),
          database.monthReviews.count(),
        ]);
        return true;
      },
      [generation],
      false,
    ) ?? false
  );
}
