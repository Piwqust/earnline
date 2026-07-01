import { describe, it, expect } from "vitest";
import {
  centsFromNumber,
  centsFromDecimalString,
  centsFromWire,
  centsToWireString,
  numberFromCents,
  parseDecimalString,
  formatMoney,
  formatCents,
} from "./money";
import { secondaryValue } from "./currency";

const NBSP = " ";

describe("money — wire encoding (SyncMoney parity)", () => {
  it("encodes 99.50 as a 2dp string", () => {
    expect(centsToWireString(centsFromNumber(99.5))).toBe("99.50");
    expect(centsToWireString(centsFromDecimalString("99.50")!)).toBe("99.50");
  });
  it("encodes large grouped money precisely", () => {
    expect(centsToWireString(centsFromNumber(123456789.12))).toBe("123456789.12");
  });
  it("encodes plain integers", () => {
    expect(centsToWireString(centsFromNumber(240))).toBe("240.00");
    expect(centsToWireString(0)).toBe("0.00");
  });
  it("decodes numbers or strings from the wire", () => {
    expect(centsFromWire("99.50")).toBe(9950);
    expect(centsFromWire(99.5)).toBe(9950);
    expect(centsFromWire("123456789.12")).toBe(12345678912);
    expect(numberFromCents(centsFromWire("240.00"))).toBe(240);
  });
});

describe("money — parsing", () => {
  it("normalizes grouped decimals", () => {
    expect(parseDecimalString("1 000")).toBe(1000);
    expect(parseDecimalString("1,250")).toBe(1250);
    expect(parseDecimalString("1,250.50")).toBe(1250.5);
    expect(parseDecimalString("99.50")).toBe(99.5);
    expect(parseDecimalString("abc")).toBeNull();
  });
});

describe("money — display (CurrencyFormatter parity)", () => {
  it("prefixes the symbol with no-break-space grouping", () => {
    expect(formatMoney(3222, "USD")).toBe(`$3${NBSP}222`);
    expect(formatCents(322200, "USD")).toBe(`$3${NBSP}222`);
  });
  it("trails the symbol for RUB and UAH", () => {
    expect(formatMoney(250513, "RUB")).toBe(`250${NBSP}513 ₽`);
  });
  it("matches the iOS secondaryString example", () => {
    // base USD, secondary RUB, rate 89.125 → secondaryString(99.50) == "8 867.94 ₽"
    const settings = { baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 89.125 };
    const value = secondaryValue(99.5, settings);
    expect(formatMoney(value, "RUB")).toBe(`8${NBSP}867.94 ₽`);
  });
});
