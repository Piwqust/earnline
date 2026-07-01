// Bundled sample ledger importer — ports Util/IncomeLedgerImporter.swift.
// Uses the same deterministic IDs as iOS so importing the sample on both clients
// merges (no duplicates) rather than colliding.

import { db } from "./db";
import type { Client, Entry } from "../domain/types";
import { parseLine } from "../domain/lineParser";
import { centsFromNumber } from "../domain/money";
import { dayMsFromParts } from "../domain/dateFormat";
import { deterministicUuid } from "../domain/deterministicId";
import { paletteColor } from "../ui/theme/theme";

export const bundledLedger = `— Income for April from Acme Studio

+ $220 Landing page wireframes
+ $180 Brand polish
+ $99.50 QA fixes

— Income for May from Northstar Labs

+ €320 Design review
+ $450 Dashboard prototype

— Income for June from River House

+ 24k ₽ Event banners
+ 11k₽ Key visuals`;

interface ParsedRecord {
  id: string;
  clientName: string;
  amountCents: number;
  currencyCode: string;
  project: string | null;
  task: string;
  date: number;
  sortIndex: number;
}

const MONTHS: Array<[string, number]> = [
  ["январ", 1], ["феврал", 2], ["март", 3], ["апрел", 4], ["май", 5], ["мая", 5],
  ["июн", 6], ["июл", 7], ["август", 8], ["сентябр", 9], ["октябр", 10], ["ноябр", 11], ["декабр", 12],
  ["january", 1], ["february", 2], ["march", 3], ["april", 4], ["may", 5], ["june", 6],
  ["july", 7], ["august", 8], ["september", 9], ["october", 10], ["november", 11], ["december", 12],
];

function normalizeKey(s: string): string {
  return s.normalize("NFD").replace(/\p{Diacritic}/gu, "").trim().toLowerCase();
}

function parseSection(line: string): { month: number; client: string } | null {
  const lower = line.toLowerCase();
  if (!lower.includes("income for") && !lower.includes("доходы за")) return null;
  const found = MONTHS.find(([k]) => lower.includes(k));
  if (!found) return null;
  let sep = " from ";
  let idx = lower.indexOf(sep);
  if (idx < 0) {
    sep = " от ";
    idx = lower.indexOf(sep);
  }
  if (idx < 0) return null;
  const client = line.slice(idx + sep.length).replace(/^[\s—-]+|[\s—-]+$/g, "").trim();
  return client ? { month: found[1], client } : null;
}

export function parseLedger(raw: string, year: number): ParsedRecord[] {
  let currentMonth: number | null = null;
  let currentClient: string | null = null;
  const sortIndexBySection = new Map<string, number>();
  const results: ParsedRecord[] = [];

  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === "") continue;

    const section = parseSection(trimmed);
    if (section) {
      currentMonth = section.month;
      currentClient = section.client;
      continue;
    }

    if (!trimmed.startsWith("+") || currentMonth == null || currentClient == null) continue;

    const sectionKey = `${year}-${currentMonth}-${normalizeKey(currentClient)}`;
    const sortIndex = sortIndexBySection.get(sectionKey) ?? 0;
    sortIndexBySection.set(sectionKey, sortIndex + 1);

    const parsed = parseLine(trimmed, "USD");
    if (parsed.amount == null) continue;

    const day = Math.min(28, sortIndex + 1);
    const task = parsed.task === "" ? "Income" : parsed.task;
    results.push({
      id: deterministicUuid(
        `earnline-entry:${year}-${currentMonth}-${normalizeKey(currentClient)}-${sortIndex}-${trimmed}`,
      ),
      clientName: currentClient,
      amountCents: centsFromNumber(parsed.amount),
      currencyCode: parsed.currencyCode,
      project: parsed.project ?? null,
      task,
      date: dayMsFromParts(year, currentMonth, day),
      sortIndex,
    });
  }
  return results;
}

export async function importBundledLedger(year = new Date().getFullYear()): Promise<number> {
  const parsed = parseLedger(bundledLedger, year);
  if (parsed.length === 0) return 0;
  let inserted = 0;

  await db.transaction("rw", db.clients, db.entries, async () => {
    const byKey = new Map((await db.clients.toArray()).map((c) => [normalizeKey(c.name), c]));
    const existingEntryIds = new Set((await db.entries.toArray()).map((e) => e.id));

    for (const rec of parsed) {
      const key = normalizeKey(rec.clientName);
      let client = byKey.get(key);
      if (!client) {
        const created: Client = {
          id: deterministicUuid(`earnline-client:${key}`),
          name: rec.clientName,
          colorHex: paletteColor(byKey.size),
          sortIndex: byKey.size,
          createdAt: rec.date,
          updatedAt: rec.date,
          syncState: "dirty",
          lastSyncedAt: null,
        };
        await db.clients.put(created);
        byKey.set(key, created);
        client = created;
        inserted += 1;
      }

      if (existingEntryIds.has(rec.id)) continue;
      const entry: Entry = {
        id: rec.id,
        clientId: client.id,
        amountCents: rec.amountCents,
        currencyCode: rec.currencyCode,
        project: rec.project,
        task: rec.task,
        date: rec.date,
        holdUntil: null,
        status: "paid",
        sortIndex: rec.sortIndex,
        createdAt: rec.date,
        updatedAt: rec.date,
        syncState: "dirty",
        lastSyncedAt: null,
      };
      await db.entries.put(entry);
      existingEntryIds.add(rec.id);
      inserted += 1;
    }
  });

  return inserted;
}
