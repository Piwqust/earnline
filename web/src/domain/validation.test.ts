import { describe, it, expect } from "vitest";
import {
  Limits,
  clampAmount,
  sanitizeAmountInput,
  capped,
  trimmed,
  validateClientName,
} from "./validation";

// Ported from earnlineTests/ValidationTests.swift
describe("Validation", () => {
  it("clamps above the maximum", () => {
    expect(clampAmount(Limits.maxAmount + 5)).toBe(Limits.maxAmount);
  });
  it("clamps negatives to zero", () => {
    expect(clampAmount(-10)).toBe(0);
  });
  it("keeps a normal amount", () => {
    expect(clampAmount(240)).toBe(240);
  });

  it("sanitize strips letters", () => {
    expect(sanitizeAmountInput("12a3b")).toBe("123");
  });
  it("sanitize keeps a single separator", () => {
    expect(sanitizeAmountInput("1.2.3")).toBe("1.23");
    expect(sanitizeAmountInput("1,50")).toBe("1.50");
  });
  it("sanitize caps the digit count", () => {
    const input = "9".repeat(30);
    expect(sanitizeAmountInput(input).length).toBe(Limits.maxAmountDigits);
  });

  it("capped truncates", () => {
    const s = "a".repeat(100);
    expect(capped(s, Limits.maxProjectLength).length).toBe(Limits.maxProjectLength);
  });
  it("trimmed trims and caps", () => {
    expect(trimmed("  hello  ", 40)).toBe("hello");
    const long = "  " + "x".repeat(200) + "  ";
    expect(trimmed(long, Limits.maxTaskLength).length).toBe(Limits.maxTaskLength);
  });

  it("client name validation trims and accepts a unique name", () => {
    expect(validateClientName("  Acme Studio  ", [])).toEqual({ kind: "valid", name: "Acme Studio" });
  });
  it("client name validation rejects empty names", () => {
    expect(validateClientName("   ", [])).toEqual({ kind: "empty" });
  });
  it("client name validation rejects case-insensitive duplicates", () => {
    expect(validateClientName("acme studio", ["Acme Studio"])).toEqual({ kind: "duplicate" });
  });
  it("client name validation applies max length", () => {
    const long = "a".repeat(Limits.maxClientNameLength + 10);
    expect(validateClientName(long, [])).toEqual({
      kind: "valid",
      name: long.slice(0, Limits.maxClientNameLength),
    });
  });
});
