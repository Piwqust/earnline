// Freeform income-line parser — direct port of Parsing/LineParser.swift.
//
// Examples it handles:
//   "+$240 Acme: 2 screens hold until 25.07.26"
//   "✅ $300 Studio X: Landing page"
//   "⌛ 140 ₽ Acme: Logotype hold 14.03"

import type { EntryStatus, ParsedLine } from "./types";
import { parseDecimalString } from "./money";
import { dayMsFromParts, todayDayMs } from "./dateFormat";

const CURRENCY_BY_SYMBOL: Record<string, string> = {
  $: "USD",
  "₽": "RUB",
  "€": "EUR",
  "£": "GBP",
  "₴": "UAH",
};

const PAID_MARKS = new Set(["✅", "✔", "✓", "☑"]);
const PROGRESS_MARKS = new Set(["⌛", "⏳", "🕓", "🟠", "🟡", "◐"]);
const CANCEL_MARKS = new Set(["❌", "✖", "✗", "🚫", "🔴"]);

const SYMBOL_CLASS = "$€₽£₴";
const NUMBER_CLASS = "0-9.,   ";
const AMOUNT_PATTERNS = [
  new RegExp(`([${SYMBOL_CLASS}])\\s?([0-9][${NUMBER_CLASS}]*[0-9]|[0-9])\\s?([kKкК])?`),
  new RegExp(`([0-9][${NUMBER_CLASS}]*[0-9]|[0-9])\\s?([kKкК])?\\s?([${SYMBOL_CLASS}])`),
];
const FALLBACK_NUMBER = new RegExp(`^([0-9][0-9.,   ]*[0-9])(?=\\s)`);
const HOLD_REGEX =
  /(?:hold\s*(?:until|till|til)?|until|till|due)\s*:?\s*(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?/i;

export function parseLine(
  raw: string,
  defaultCurrency = "USD",
  referenceDayMs: number = todayDayMs(),
): ParsedLine {
  const result: ParsedLine = { currencyCode: defaultCurrency, task: "" };
  let working = raw.trim();

  // 1) Leading status marker (emoji)
  const status = leadingStatus(working);
  if (status.status) result.status = status.status;
  working = status.rest;

  // 2) "hold until <date>" phrase (remove so its digits don't confuse the amount)
  const hold = extractHoldDate(working, referenceDayMs);
  if (hold) {
    result.holdUntil = hold.date;
    working = hold.rest;
  }

  // 3) Amount + currency
  const amount = extractAmount(working);
  if (amount) {
    result.amount = amount.value;
    result.currencyCode = amount.code ?? defaultCurrency;
    working = amount.rest;
  }

  // 4) "Project : Task"
  working = trimChars(working, " +\t·");
  const colon = working.indexOf(":");
  if (colon >= 0) {
    const left = working.slice(0, colon).trim();
    const right = working.slice(colon + 1).trim();
    result.project = left === "" ? undefined : left;
    result.task = right;
  } else {
    result.task = working;
  }
  return result;
}

function leadingStatus(s: string): { status?: EntryStatus; rest: string } {
  let chars = Array.from(s);
  let status: EntryStatus | undefined;
  let consumed = true;
  while (consumed && chars.length > 0) {
    consumed = false;
    const first = chars[0];
    if (PAID_MARKS.has(first)) {
      status = "paid";
      consumed = true;
    } else if (PROGRESS_MARKS.has(first)) {
      status = "inProgress";
      consumed = true;
    } else if (CANCEL_MARKS.has(first)) {
      status = "canceled";
      consumed = true;
    } else if (first === "+" || /\s/.test(first) || first === "️") {
      consumed = true; // strip decoration / variation selector
    }
    if (consumed) chars = chars.slice(1);
  }
  return { status, rest: chars.join("").trim() };
}

function extractAmount(s: string): { value: number; code: string | null; rest: string } | null {
  for (let i = 0; i < AMOUNT_PATTERNS.length; i++) {
    const m = AMOUNT_PATTERNS[i].exec(s);
    if (!m) continue;
    const numberStr = i === 0 ? m[2] : m[1];
    const multiplier = i === 0 ? m[3] : m[2];
    const symbol = i === 0 ? m[1] : m[3];
    let value = parseDecimalString(numberStr);
    if (value == null) continue;
    if (multiplier != null) value *= 1000;
    const code = symbol ? CURRENCY_BY_SYMBOL[symbol] ?? null : null;
    const rest = (s.slice(0, m.index) + s.slice(m.index + m[0].length)).trim();
    return { value, code, rest };
  }

  // Fallback: a leading bare number (2+ digits), e.g. "240 Acme: ..."
  const fb = FALLBACK_NUMBER.exec(s);
  if (fb) {
    const value = parseDecimalString(fb[1]);
    if (value != null) {
      const rest = s.slice(fb[0].length).trim();
      return { value, code: null, rest };
    }
  }
  return null;
}

function extractHoldDate(s: string, referenceDayMs: number): { date: number; rest: string } | null {
  const m = HOLD_REGEX.exec(s);
  if (!m) return null;
  const day = parseInt(m[1], 10);
  const month = parseInt(m[2], 10);
  if (!(month >= 1 && month <= 12 && day >= 1 && day <= 31)) return null;

  let year = new Date(referenceDayMs).getUTCFullYear();
  let hasExplicitYear = false;
  if (m[3] != null) {
    const y = parseInt(m[3], 10);
    year = y < 100 ? 2000 + y : y;
    hasExplicitYear = true;
  }

  let date = dayMsFromParts(year, month, day);
  if (!hasExplicitYear && date < referenceDayMs) {
    date = dayMsFromParts(year + 1, month, day);
  }
  const rest = (s.slice(0, m.index) + s.slice(m.index + m[0].length)).trim();
  return { date, rest };
}

function trimChars(s: string, set: string): string {
  let start = 0;
  let end = s.length;
  while (start < end && set.includes(s[start])) start += 1;
  while (end > start && set.includes(s[end - 1])) end -= 1;
  return s.slice(start, end);
}
