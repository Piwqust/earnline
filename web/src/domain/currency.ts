// Currency conversion + settings normalization — ports the currency logic from
// ViewModels/AppModel.swift. Amounts here are dollars (numbers), not cents.

import { SUPPORTED_CURRENCY_CODES } from "./money";

export const DEFAULT_BASE_CURRENCY = "USD";
export const DEFAULT_SECONDARY_CURRENCY = "RUB";
export const DEFAULT_EXCHANGE_RATE = 83;

const SUPPORTED: readonly string[] = SUPPORTED_CURRENCY_CODES;

export interface CurrencySettings {
  baseCurrencyCode: string;
  secondaryCurrencyCode: string;
  rate: number; // secondary units per 1 base unit
}

/** Base-currency value of one unit of `code`, or null when there is no rate. */
export function conversionRate(code: string, s: CurrencySettings): number | null {
  if (code === s.baseCurrencyCode) return 1;
  if (code === s.secondaryCurrencyCode) return 1 / s.rate;
  return null;
}

export function canConvert(code: string, s: CurrencySettings): boolean {
  return conversionRate(code, s) !== null;
}

/** Convert an amount in `code` into the base currency, or null without a rate. */
export function convertToBase(amount: number, code: string, s: CurrencySettings): number | null {
  const rate = conversionRate(code, s);
  return rate == null ? null : amount * rate;
}

/**
 * Numeric compatibility helper for aggregate callers. Unsupported currencies
 * are excluded (0), never silently treated as 1:1. Use `convertToBase` when the
 * UI needs to distinguish an incomplete conversion from an actual zero.
 */
export function toBase(amount: number, code: string, s: CurrencySettings): number {
  return convertToBase(amount, code, s) ?? 0;
}

/** The secondary-currency value for a base amount. */
export function secondaryValue(base: number, s: CurrencySettings): number {
  return base * s.rate;
}

export function validExchangeRate(value: number, fallback: number = DEFAULT_EXCHANGE_RATE): number {
  if (Number.isFinite(value) && value > 0) return value;
  if (Number.isFinite(fallback) && fallback > 0) return fallback;
  return DEFAULT_EXCHANGE_RATE;
}

export function normalizedCurrencyCode(code: string | null | undefined, fallback: string): string {
  const normalized = (code ?? "").trim().toUpperCase();
  if (SUPPORTED.includes(normalized)) return normalized;
  return SUPPORTED.includes(fallback) ? fallback : DEFAULT_BASE_CURRENCY;
}

export function replacementCurrencyCode(excluding: string): string {
  return SUPPORTED.find((c) => c !== excluding) ?? DEFAULT_SECONDARY_CURRENCY;
}
