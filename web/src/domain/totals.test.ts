import { describe, it, expect } from "vitest";
import type { Client, Entry } from "./types";
import { entriesOf, earnedEntriesOf, totalOf, monthTotal } from "./totals";
import { dayMsFromParts } from "./dateFormat";

const settings = { baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 100 };

function entry(partial: Partial<Entry> & Pick<Entry, "amountCents" | "status" | "sortIndex">): Entry {
  return {
    id: crypto.randomUUID(),
    clientId: "c1",
    currencyCode: "USD",
    task: "t",
    date: dayMsFromParts(2026, 6, 15),
    createdAt: 0,
    syncState: "dirty",
    ...partial,
  };
}

// Ported from SyncModelTests.canceledEntriesAreExcludedFromEarnedTotals
describe("totals — canceled excluded from earned", () => {
  const month = dayMsFromParts(2026, 6, 15);
  const client: Client = {
    id: "c1",
    name: "Acme Studio",
    colorHex: "#0088FF",
    sortIndex: 0,
    createdAt: 0,
    syncState: "dirty",
  };
  const entries: Entry[] = [
    entry({ amountCents: 10000, status: "paid", sortIndex: 0 }),
    entry({ amountCents: 5000, status: "inProgress", sortIndex: 1 }),
    entry({ amountCents: 2500, status: "canceled", sortIndex: 2 }),
  ];

  it("excludes canceled lines from totals but not from listings", () => {
    expect(totalOf("c1", entries, month, settings)).toBe(150);
    expect(monthTotal([client], entries, month, settings)).toBe(150);
    expect(entriesOf("c1", entries, month).length).toBe(3);
    expect(earnedEntriesOf("c1", entries, month).length).toBe(2);
  });
});
