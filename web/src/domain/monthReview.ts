import { inputValueFromDayMs, monthStartDayMs } from "./dateFormat";
import { deterministicUuid } from "./deterministicId";

export const MONTH_REVIEW_MAX_NOTE_LENGTH = 280;

/** Canonical first UTC day of a reviewed calendar month. */
export function monthReviewMonthStart(monthContaining: number): number {
  return monthStartDayMs(monthContaining);
}

/** Must match `MonthReview.id(for:)` in the iOS client. */
export function monthReviewId(monthContaining: number): string {
  const monthStart = monthReviewMonthStart(monthContaining);
  return deterministicUuid(`earnline-month-review:${inputValueFromDayMs(monthStart)}`);
}

export function isValidMonthReviewNote(note: string): boolean {
  // `Array.from` walks Unicode code points, matching Swift's
  // `unicodeScalars.count` and Postgres `char_length` better than UTF-16
  // `String.length` for emoji and non-Latin text.
  return Array.from(note).length <= MONTH_REVIEW_MAX_NOTE_LENGTH;
}

export function validateMonthReviewNote(note: string): void {
  if (!isValidMonthReviewNote(note)) {
    throw new Error(`A month note can contain up to ${MONTH_REVIEW_MAX_NOTE_LENGTH} characters.`);
  }
}
