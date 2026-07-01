// Money — integer-cents representation + wire encoding + display formatting.
// Ports RemoteRecords.SyncMoney (wire) and CurrencyFormatter (display) from iOS.

export type Cents = number;

export const SUPPORTED_CURRENCY_CODES = ["USD", "EUR", "GBP", "RUB", "UAH"] as const;
export type CurrencyCode = (typeof SUPPORTED_CURRENCY_CODES)[number];

const SYMBOLS: Record<string, string> = {
  USD: "$",
  RUB: "₽",
  EUR: "€",
  GBP: "£",
  UAH: "₴",
};

// Currencies that carry no minor unit (mirrors CurrencyFormatter.fractionDigits).
const ZERO_DECIMAL = new Set([
  "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA",
  "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
]);

export function currencySymbol(code: string): string {
  return SYMBOLS[code] ?? code;
}

export function fractionDigits(code: string): number {
  return ZERO_DECIMAL.has(code) ? 0 : 2;
}

// --- parsing ---

/**
 * Normalize a grouped numeric string ("1 000", "1,250.50") into a number.
 * Direct port of LineParser.decimal(from:).
 */
export function parseDecimalString(raw: string): number | null {
  let s = raw
    .replace(/ /g, "")
    .replace(/ /g, "")
    .replace(/ /g, "");
  const hasComma = s.includes(",");
  const hasDot = s.includes(".");
  if (hasComma && hasDot) {
    s = s.replace(/,/g, ""); // comma = thousands
  } else if (hasComma) {
    const parts = s.split(",");
    if (parts.length === 2 && parts[1].length <= 2) {
      s = s.replace(",", ".");
    } else {
      s = s.replace(/,/g, "");
    }
  } else if (hasDot) {
    const parts = s.split(".");
    if (!(parts.length === 2 && parts[1].length <= 2)) {
      s = s.replace(/\./g, "");
    }
  }
  if (s === "" || s === "." || s === "-" || s === "-.") return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

// --- cents conversions ---

export function centsFromNumber(n: number): Cents {
  return Math.round(n * 100);
}

export function numberFromCents(c: Cents): number {
  return c / 100;
}

export function centsFromDecimalString(raw: string): Cents | null {
  const n = parseDecimalString(raw);
  return n == null ? null : centsFromNumber(n);
}

// --- wire (matches SyncMoney: en_US_POSIX, no grouping, exactly 2 dp) ---

export function centsToWireString(cents: Cents): string {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(Math.trunc(cents));
  const whole = Math.trunc(abs / 100);
  const minor = abs % 100;
  return `${sign}${whole}.${minor.toString().padStart(2, "0")}`;
}

/** Decode a numeric column value (PostgREST returns number or string). */
export function centsFromWire(value: string | number): Cents {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
}

// --- display (matches CurrencyFormatter) ---

/** Space-grouped (no-break space) thousands, up to the currency's fraction digits. */
export function groupedNumber(value: number, code: string): string {
  const formatted = new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: fractionDigits(code),
    useGrouping: true,
  }).format(value);
  return formatted.replace(/,/g, " ");
}

/** Symbol-prefixed ("$3 222"); currencies whose symbol trails (₽, ₴) go after. */
export function formatMoney(value: number, code: string): string {
  const symbol = currencySymbol(code);
  const number = groupedNumber(value, code);
  if (code === "RUB" || code === "UAH") {
    return `${number} ${symbol}`;
  }
  return `${symbol}${number}`;
}

/** Convenience: format a cents amount in its own currency. */
export function formatCents(cents: Cents, code: string): string {
  return formatMoney(numberFromCents(cents), code);
}
