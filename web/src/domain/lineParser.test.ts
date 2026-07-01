import { describe, it, expect } from "vitest";
import { parseLine } from "./lineParser";
import { isCommittable } from "./types";
import { dayMsFromParts } from "./dateFormat";

function ymd(ms: number) {
  const d = new Date(ms);
  return { day: d.getUTCDate(), month: d.getUTCMonth() + 1, year: d.getUTCFullYear() };
}

// Ported case-for-case from earnlineTests/LineParserTests.swift
describe("LineParser", () => {
  it("parses dollar amount, project and task", () => {
    const p = parseLine("+$240 Acme: 2 screens");
    expect(p.amount).toBe(240);
    expect(p.currencyCode).toBe("USD");
    expect(p.project).toBe("Acme");
    expect(p.task).toBe("2 screens");
  });

  it("parses paid marker", () => {
    const p = parseLine("✅ $300 Studio X: Landing page");
    expect(p.status).toBe("paid");
    expect(p.amount).toBe(300);
    expect(p.project).toBe("Studio X");
    expect(p.task).toBe("Landing page");
  });

  it("parses hold until date", () => {
    const p = parseLine("⌛ $140 Acme: Logotype hold until 14.03.26");
    expect(p.status).toBe("inProgress");
    expect(p.amount).toBe(140);
    expect(p.project).toBe("Acme");
    expect(p.task).toBe("Logotype");
    expect(ymd(p.holdUntil!)).toEqual({ day: 14, month: 3, year: 2026 });
  });

  it("rolls a yearless hold date into the future year", () => {
    const reference = dayMsFromParts(2026, 12, 20);
    const p = parseLine("$140 Acme: Logotype hold 14.01", "USD", reference);
    expect(ymd(p.holdUntil!)).toEqual({ day: 14, month: 1, year: 2027 });
  });

  it("keeps a yearless future hold date in the current year", () => {
    const reference = dayMsFromParts(2026, 1, 3);
    const p = parseLine("$140 Acme: Logotype hold 14.01", "USD", reference);
    expect(ymd(p.holdUntil!)).toEqual({ day: 14, month: 1, year: 2026 });
  });

  it("parses space-grouped thousands", () => {
    const p = parseLine("$1 000 Northstar: Telegram bot");
    expect(p.amount).toBe(1000);
    expect(p.project).toBe("Northstar");
  });

  it("parses comma thousands", () => {
    const p = parseLine("$1,250 Acme: Website");
    expect(p.amount).toBe(1250);
  });

  it("parses decimal amount", () => {
    const p = parseLine("$99.50 Acme: Fix");
    expect(p.amount).toBe(99.5);
  });

  it("parses ruble suffix", () => {
    const p = parseLine("12 000 ₽ Local: Banner");
    expect(p.currencyCode).toBe("RUB");
    expect(p.amount).toBe(12000);
  });

  it("parses thousands suffix before currency", () => {
    const p = parseLine("24k ₽");
    expect(p.currencyCode).toBe("RUB");
    expect(p.amount).toBe(24000);
  });

  it("parses thousands suffix tight to currency", () => {
    const p = parseLine("+ 11k₽ River: KVs");
    expect(p.currencyCode).toBe("RUB");
    expect(p.amount).toBe(11000);
    expect(p.project).toBe("River");
    expect(p.task).toBe("KVs");
  });

  it("parses a leading bare number", () => {
    const p = parseLine("240 Acme: Two screens");
    expect(p.amount).toBe(240);
    expect(p.project).toBe("Acme");
  });

  it("no colon means task only", () => {
    const p = parseLine("$50 quick fix");
    expect(p.amount).toBe(50);
    expect(p.project).toBeUndefined();
    expect(p.task).toBe("quick fix");
  });

  it("does not mistake a short digit for an amount", () => {
    const p = parseLine("2 screens for the homepage");
    expect(p.amount).toBeUndefined();
    expect(p.task).toBe("2 screens for the homepage");
  });

  it("committable requires amount and text", () => {
    expect(isCommittable(parseLine("$240 Acme: 2 screens"))).toBe(true);
    expect(isCommittable(parseLine("Acme: 2 screens"))).toBe(false);
  });
});
