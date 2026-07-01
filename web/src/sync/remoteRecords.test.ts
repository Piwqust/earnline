import { describe, it, expect } from "vitest";
import type { Client, Entry } from "../domain/types";
import { centsFromNumber } from "../domain/money";
import { dayMsFromParts } from "../domain/dateFormat";
import {
  clientToRow,
  entryToRow,
  parseDay,
  parseTimestamp,
  rowToEntry,
  timestampString,
} from "./remoteRecords";

function makeEntry(amount: number, status: Entry["status"]): Entry {
  return {
    id: "entry-1",
    clientId: "client-1",
    amountCents: centsFromNumber(amount),
    currencyCode: "USD",
    project: null,
    task: "QA fixes",
    date: dayMsFromParts(2026, 6, 30),
    holdUntil: null,
    status,
    sortIndex: 0,
    createdAt: Date.UTC(2026, 5, 30, 12, 0, 0),
    updatedAt: Date.UTC(2026, 5, 30, 12, 0, 0),
    syncState: "dirty",
    lastSyncedAt: null,
  };
}

// Mirrors SyncModelTests.swift — the wire shape must match the iOS DTOs exactly.
describe("remoteRecords — wire parity", () => {
  it("encodes money as a 2dp decimal string and snake_case keys", () => {
    const row = entryToRow(makeEntry(99.5, "canceled"), "test-workspace");
    expect(row.amount).toBe("99.50");
    expect(row.status).toBe("canceled");
    expect(row.client_id).toBe("client-1");
    expect(row.currency_code).toBe("USD");
    expect(row.date).toBe("2026-06-30");
    expect(row.workspace_id).toBe("test-workspace");
  });

  it("encodes large grouped money precisely", () => {
    const row = entryToRow(makeEntry(123456789.12, "paid"), "test-workspace");
    expect(row.amount).toBe("123456789.12");
  });

  it("encodes a client with snake_case keys", () => {
    const client: Client = {
      id: "client-1",
      name: "Acme Studio",
      colorHex: "#0088FF",
      sortIndex: 2,
      createdAt: Date.UTC(2026, 5, 1, 0, 0, 0),
      updatedAt: Date.UTC(2026, 5, 2, 0, 0, 0),
      syncState: "dirty",
      lastSyncedAt: null,
    };
    const row = clientToRow(client, "test-workspace");
    expect(row.color_hex).toBe("#0088FF");
    expect(row.sort_index).toBe(2);
    expect(row.updated_at).toBe(timestampString(client.updatedAt!));
  });

  it("round-trips an entry through the wire", () => {
    const original = makeEntry(1250.5, "inProgress");
    const row = entryToRow(original, "ws");
    const back = rowToEntry(
      { ...row, amount: row.amount, workspace_id: "ws" },
      Date.now(),
    );
    expect(back.amountCents).toBe(original.amountCents);
    expect(back.status).toBe("inProgress");
    expect(back.date).toBe(original.date);
    expect(back.clientId).toBe("client-1");
    expect(back.syncState).toBe("synced");
  });

  it("round-trips days and timestamps", () => {
    const day = dayMsFromParts(2026, 1, 5);
    expect(parseDay("2026-01-05")).toBe(day);
    const ts = Date.UTC(2026, 0, 5, 9, 30, 15, 250);
    expect(parseTimestamp(timestampString(ts))).toBe(ts);
  });
});
