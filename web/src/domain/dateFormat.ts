// Date helpers — ports Theme/DateFormat.swift and the day/month grouping logic.
// Everything is epoch-ms based. "Day" values are UTC-midnight of a calendar day
// and are formatted with UTC components so the picked day shows everywhere.

export function nowMs(): number {
  return Date.now();
}

/** UTC-midnight of the user's local "today". */
export function todayDayMs(): number {
  const n = new Date();
  return Date.UTC(n.getFullYear(), n.getMonth(), n.getDate());
}

export function dayMsFromParts(year: number, month1: number, day: number): number {
  return Date.UTC(year, month1 - 1, day);
}

/** Parse an <input type="date"> value ("YYYY-MM-DD") to a UTC-midnight day. */
export function dayMsFromInputValue(value: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!m) return null;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

/** Format a day to an <input type="date"> value. */
export function inputValueFromDayMs(ms: number): string {
  const d = new Date(ms);
  return (
    `${d.getUTCFullYear().toString().padStart(4, "0")}-` +
    `${(d.getUTCMonth() + 1).toString().padStart(2, "0")}-` +
    `${d.getUTCDate().toString().padStart(2, "0")}`
  );
}

function pad2(n: number): string {
  return n.toString().padStart(2, "0");
}

/** DD.MM.YY for a day-valued date (UTC components). */
export function dottedDay(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getUTCDate())}.${pad2(d.getUTCMonth() + 1)}.${pad2(d.getUTCFullYear() % 100)}`;
}

/** DD.MM.YY for a real instant (local components) — used for "last sync". */
export function dottedInstant(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${pad2(d.getFullYear() % 100)}`;
}

const MONTH_FMT = new Intl.DateTimeFormat("en-US", { month: "long", timeZone: "UTC" });

/** Full capitalized month name of a day ("June"). */
export function monthNameOfDay(ms: number): string {
  return MONTH_FMT.format(new Date(ms));
}

/** First day of the month containing `ms` (UTC-midnight) — grouping key. */
export function monthStartDayMs(ms: number): number {
  const d = new Date(ms);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1);
}

export function sameMonthDay(a: number, b: number): boolean {
  const da = new Date(a);
  const db = new Date(b);
  return da.getUTCFullYear() === db.getUTCFullYear() && da.getUTCMonth() === db.getUTCMonth();
}

export function isCurrentMonthDay(ms: number): boolean {
  return sameMonthDay(ms, todayDayMs());
}
