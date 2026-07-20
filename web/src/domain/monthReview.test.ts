import { describe, expect, it } from "vitest";
import { dayMsFromParts } from "./dateFormat";
import {
  MONTH_REVIEW_MAX_NOTE_LENGTH,
  monthReviewId,
  monthReviewMonthStart,
  validateMonthReviewNote,
} from "./monthReview";

describe("monthReview", () => {
  it("uses one deterministic ID for every day in the same month, including January", () => {
    const januaryFirst = dayMsFromParts(2026, 1, 1);
    expect(monthReviewMonthStart(dayMsFromParts(2026, 1, 31))).toBe(januaryFirst);
    expect(monthReviewId(dayMsFromParts(2026, 1, 1))).toBe(monthReviewId(dayMsFromParts(2026, 1, 31)));
    // Shared with MonthReviewTests.swift: catches iOS/web namespace drift.
    expect(monthReviewId(januaryFirst)).toBe("f1010a14-d16f-52d3-92b6-57d1f655d082");
  });

  it("rejects notes that exceed the shared storage limit", () => {
    expect(() => validateMonthReviewNote("x".repeat(MONTH_REVIEW_MAX_NOTE_LENGTH))).not.toThrow();
    expect(() => validateMonthReviewNote("x".repeat(MONTH_REVIEW_MAX_NOTE_LENGTH + 1))).toThrow("month note");
  });

  it("counts emoji as one shared storage character", () => {
    expect(() => validateMonthReviewNote("🪙".repeat(MONTH_REVIEW_MAX_NOTE_LENGTH))).not.toThrow();
    expect(() => validateMonthReviewNote("🪙".repeat(MONTH_REVIEW_MAX_NOTE_LENGTH + 1))).toThrow("month note");
  });
});
