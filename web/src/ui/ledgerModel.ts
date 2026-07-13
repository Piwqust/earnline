import { convertToBase, type CurrencySettings } from "../domain/currency";
import { monthStartDayMs, todayDayMs } from "../domain/dateFormat";
import { numberFromCents } from "../domain/money";
import {
  isIncludedInEarnedTotals,
  STATUS_ORDER,
  type Client,
  type Entry,
  type EntryStatus,
  type Heading,
} from "../domain/types";

export type LedgerBlock =
  | { kind: "heading"; heading: Heading; sortIndex: number; createdAt: number }
  | {
      kind: "client";
      client: Client;
      entries: Entry[];
      total: number;
      unsupportedCount: number;
      sortIndex: number;
      createdAt: number;
    };

export interface LedgerMonthModel {
  month: number;
  blocks: LedgerBlock[];
  total: number;
  lineCount: number;
  unsupportedCount: number;
}

export interface LedgerModel {
  months: number[];
  byMonth: Map<number, LedgerMonthModel>;
}

export interface ClientDetailModel {
  entries: Entry[];
  total: number;
  unsupportedCount: number;
  projects: Array<{ name: string; sum: number }>;
  statuses: Array<{ status: EntryStatus; count: number; sum: number }>;
}

interface MonthBucket {
  entriesByClient: Map<string, Entry[]>;
  headings: Heading[];
  lineCount: number;
}

function bucketFor(map: Map<number, MonthBucket>, month: number): MonthBucket {
  const existing = map.get(month);
  if (existing) return existing;
  const created: MonthBucket = { entriesByClient: new Map(), headings: [], lineCount: 0 };
  map.set(month, created);
  return created;
}

export function buildLedgerModel(
  clients: Client[],
  entries: Entry[],
  headings: Heading[],
  currency: CurrencySettings,
): LedgerModel {
  const buckets = new Map<number, MonthBucket>();
  bucketFor(buckets, monthStartDayMs(todayDayMs()));

  for (const entry of entries) {
    const bucket = bucketFor(buckets, monthStartDayMs(entry.date));
    const list = bucket.entriesByClient.get(entry.clientId) ?? [];
    list.push(entry);
    bucket.entriesByClient.set(entry.clientId, list);
    bucket.lineCount += 1;
  }
  for (const heading of headings) bucketFor(buckets, monthStartDayMs(heading.date)).headings.push(heading);

  const clientById = new Map(clients.map((client) => [client.id, client]));
  const months = [...buckets.keys()].sort((left, right) => right - left);
  const byMonth = new Map<number, LedgerMonthModel>();

  for (const month of months) {
    const bucket = buckets.get(month)!;
    const blocks: LedgerBlock[] = bucket.headings.map((heading) => ({
      kind: "heading",
      heading,
      sortIndex: heading.sortIndex,
      createdAt: heading.createdAt,
    }));
    let total = 0;
    let unsupportedCount = 0;

    for (const [clientId, unsorted] of bucket.entriesByClient) {
      const client = clientById.get(clientId);
      if (!client) continue;
      const clientEntries = [...unsorted].sort((left, right) =>
        left.sortIndex === right.sortIndex ? right.createdAt - left.createdAt : left.sortIndex - right.sortIndex,
      );
      let clientTotal = 0;
      let clientUnsupported = 0;
      for (const entry of clientEntries) {
        if (!isIncludedInEarnedTotals(entry.status)) continue;
        const converted = convertToBase(numberFromCents(entry.amountCents), entry.currencyCode, currency);
        if (converted == null) clientUnsupported += 1;
        else clientTotal += converted;
      }
      total += clientTotal;
      unsupportedCount += clientUnsupported;
      blocks.push({
        kind: "client",
        client,
        entries: clientEntries,
        total: clientTotal,
        unsupportedCount: clientUnsupported,
        sortIndex: client.sortIndex,
        createdAt: client.createdAt,
      });
    }

    blocks.sort((left, right) =>
      left.sortIndex === right.sortIndex ? left.createdAt - right.createdAt : left.sortIndex - right.sortIndex,
    );
    byMonth.set(month, { month, blocks, total, lineCount: bucket.lineCount, unsupportedCount });
  }

  return { months, byMonth };
}

/** Build every client-detail breakdown in one pass over the shared entry list. */
export function buildClientDetailModel(
  clientId: string,
  allEntries: Entry[],
  currency: CurrencySettings,
): ClientDetailModel {
  const entries: Entry[] = [];
  const projects = new Map<string, number>();
  const statuses = new Map(STATUS_ORDER.map((status) => [status, { status, count: 0, sum: 0 }]));
  let total = 0;
  let unsupportedCount = 0;

  for (const entry of allEntries) {
    if (entry.clientId !== clientId) continue;
    entries.push(entry);
    const converted = convertToBase(numberFromCents(entry.amountCents), entry.currencyCode, currency);
    const status = statuses.get(entry.status)!;
    status.count += 1;
    if (converted != null) status.sum += converted;

    if (!isIncludedInEarnedTotals(entry.status)) continue;
    const project = entry.project?.trim() || "—";
    if (!projects.has(project)) projects.set(project, 0);
    if (converted == null) {
      unsupportedCount += 1;
      continue;
    }
    total += converted;
    projects.set(project, (projects.get(project) ?? 0) + converted);
  }

  entries.sort((left, right) =>
    left.date === right.date ? right.createdAt - left.createdAt : right.date - left.date,
  );
  return {
    entries,
    total,
    unsupportedCount,
    projects: [...projects].sort((left, right) => right[1] - left[1]).map(([name, sum]) => ({ name, sum })),
    statuses: STATUS_ORDER.map((status) => statuses.get(status)!).filter((row) => row.count > 0),
  };
}
