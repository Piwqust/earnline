import { describe, it, expect } from "vitest";
import {
  DEFAULT_EXCHANGE_RATE,
  canConvert,
  conversionRate,
  toBase,
  validExchangeRate,
} from "./currency";

const settings = { baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 100 };

// Ported from SyncModelTests.invalidExchangeRatesFallBackToSafeValues
describe("currency — exchange rate validation", () => {
  it("falls back to a safe value", () => {
    expect(validExchangeRate(0, 42)).toBe(42);
    expect(validExchangeRate(-1, 42)).toBe(42);
    expect(validExchangeRate(Number.NaN, -1)).toBe(DEFAULT_EXCHANGE_RATE);
    expect(validExchangeRate(Number.POSITIVE_INFINITY, 42)).toBe(42);
  });
});

describe("currency — conversion", () => {
  it("converts base, secondary and unsupported codes", () => {
    expect(conversionRate("USD", settings)).toBe(1);
    expect(conversionRate("RUB", settings)).toBe(1 / 100);
    expect(conversionRate("EUR", settings)).toBeNull();

    expect(canConvert("USD", settings)).toBe(true);
    expect(canConvert("EUR", settings)).toBe(false);

    expect(toBase(100, "USD", settings)).toBe(100);
    expect(toBase(1000, "RUB", settings)).toBe(10);
    expect(toBase(100, "EUR", settings)).toBe(100); // lossy 1:1 fallback
  });
});
