import { describe, expect, it } from "vitest";
import type { Entry } from "../domain/types";
import { buildClientDetailModel } from "./ledgerModel";

function entry(partial: Partial<Entry> & Pick<Entry, "id" | "amountCents" | "currencyCode" | "status">): Entry {
  return {
    clientId: "client-1",
    task: partial.id,
    date: Date.UTC(2026, 6, 12),
    sortIndex: 0,
    createdAt: 1,
    syncState: "synced",
    ...partial,
  };
}

describe("buildClientDetailModel", () => {
  it("builds totals, status rows, projects, and unsupported counts in one pass", () => {
    const model = buildClientDetailModel(
      "client-1",
      [
        entry({ id: "paid", amountCents: 10000, currencyCode: "USD", status: "paid", project: "Alpha" }),
        entry({ id: "progress", amountCents: 830000, currencyCode: "RUB", status: "inProgress", project: "Alpha" }),
        entry({ id: "canceled", amountCents: 5000, currencyCode: "USD", status: "canceled", project: "Canceled" }),
        entry({ id: "unsupported", amountCents: 2000, currencyCode: "EUR", status: "paid", project: "Beta" }),
        entry({
          id: "other-client",
          clientId: "client-2",
          amountCents: 99900,
          currencyCode: "USD",
          status: "paid",
        }),
      ],
      { baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 83 },
    );

    expect(model.entries).toHaveLength(4);
    expect(model.total).toBe(200);
    expect(model.unsupportedCount).toBe(1);
    expect(model.projects).toEqual([
      { name: "Alpha", sum: 200 },
      { name: "Beta", sum: 0 },
    ]);
    expect(model.statuses).toEqual([
      { status: "paid", count: 2, sum: 100 },
      { status: "inProgress", count: 1, sum: 100 },
      { status: "canceled", count: 1, sum: 50 },
    ]);
  });
});
