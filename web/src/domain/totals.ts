// Grouping + totals — ports the grouping/total logic from AppModel.swift and the
// per-client breakdowns from ClientDetailView.swift. Operates on the flat web
// entry/client arrays (entries carry clientId).

import type { Client, Entry, EntryStatus } from "./types";
import { isIncludedInEarnedTotals } from "./types";
import { toBase, type CurrencySettings } from "./currency";
import { numberFromCents } from "./money";
import { monthStartDayMs, sameMonthDay, todayDayMs } from "./dateFormat";

function baseAmount(e: Entry, s: CurrencySettings): number {
  return toBase(numberFromCents(e.amountCents), e.currencyCode, s);
}

export function entriesOf(clientId: string, entries: Entry[], monthMs: number): Entry[] {
  return entries
    .filter((e) => e.clientId === clientId && sameMonthDay(e.date, monthMs))
    .sort((a, b) => (a.sortIndex === b.sortIndex ? b.createdAt - a.createdAt : a.sortIndex - b.sortIndex));
}

export function earnedEntriesOf(clientId: string, entries: Entry[], monthMs: number): Entry[] {
  return entriesOf(clientId, entries, monthMs).filter((e) => isIncludedInEarnedTotals(e.status));
}

export function totalOf(clientId: string, entries: Entry[], monthMs: number, s: CurrencySettings): number {
  return earnedEntriesOf(clientId, entries, monthMs).reduce((sum, e) => sum + baseAmount(e, s), 0);
}

export function clientsWithEntries(clients: Client[], entries: Entry[], monthMs: number): Client[] {
  return clients
    .filter((c) => entriesOf(c.id, entries, monthMs).length > 0)
    .sort((a, b) => a.sortIndex - b.sortIndex);
}

export function monthTotal(clients: Client[], entries: Entry[], monthMs: number, s: CurrencySettings): number {
  return clients.reduce((sum, c) => sum + totalOf(c.id, entries, monthMs, s), 0);
}

/** Months containing at least one entry (newest first), always including this month. */
export function monthsWithData(entries: Entry[]): number[] {
  const set = new Set<number>();
  for (const e of entries) set.add(monthStartDayMs(e.date));
  set.add(monthStartDayMs(todayDayMs()));
  return [...set].sort((a, b) => b - a);
}

// --- per-client breakdowns (ClientDetailView) ---

export function clientEntries(clientId: string, entries: Entry[]): Entry[] {
  return entries.filter((e) => e.clientId === clientId);
}

export function clientTotalAll(clientId: string, entries: Entry[], s: CurrencySettings): number {
  return clientEntries(clientId, entries)
    .filter((e) => isIncludedInEarnedTotals(e.status))
    .reduce((sum, e) => sum + baseAmount(e, s), 0);
}

export function statusTotal(
  clientId: string,
  entries: Entry[],
  status: EntryStatus,
  s: CurrencySettings,
): { count: number; sum: number } {
  const items = clientEntries(clientId, entries).filter((e) => e.status === status);
  return { count: items.length, sum: items.reduce((sum, e) => sum + baseAmount(e, s), 0) };
}

export function projectTotals(
  clientId: string,
  entries: Entry[],
  s: CurrencySettings,
): { name: string; sum: number }[] {
  const dict = new Map<string, number>();
  for (const e of clientEntries(clientId, entries)) {
    if (!isIncludedInEarnedTotals(e.status)) continue;
    const key = e.project && e.project !== "" ? e.project : "—";
    dict.set(key, (dict.get(key) ?? 0) + baseAmount(e, s));
  }
  return [...dict.entries()].sort((a, b) => b[1] - a[1]).map(([name, sum]) => ({ name, sum }));
}
