// Validation + limits — direct port of Util/Validation.swift.

export const Limits = {
  maxAmount: 1_000_000_000,
  maxAmountDigits: 12,
  maxProjectLength: 40,
  maxTaskLength: 140,
  maxClientNameLength: 24,
  maxHeadingLength: 40,
} as const;

/** Clamp an amount (dollars) into (0, maxAmount]. */
export function clampAmount(value: number): number {
  if (value < 0) return 0;
  return Math.min(value, Limits.maxAmount);
}

/** Keep only digits and a single decimal separator (capped digits) as the user types. */
export function sanitizeAmountInput(raw: string): string {
  let out = "";
  let seenSeparator = false;
  let digitCount = 0;
  for (const ch of raw) {
    if (ch >= "0" && ch <= "9") {
      if (digitCount >= Limits.maxAmountDigits) continue;
      out += ch;
      digitCount += 1;
    } else if (ch === "." || ch === ",") {
      if (seenSeparator) continue;
      seenSeparator = true;
      out += ".";
    }
  }
  return out;
}

function countChars(s: string): string[] {
  return Array.from(s);
}

export function trimmed(s: string, max: number): string {
  const t = s.trim();
  const chars = countChars(t);
  return chars.length <= max ? t : chars.slice(0, max).join("");
}

/** Cap a string's length while editing (no trim, so trailing spaces are allowed mid-type). */
export function capped(s: string, max: number): string {
  const chars = countChars(s);
  return chars.length <= max ? s : chars.slice(0, max).join("");
}

export type ClientNameValidation =
  | { kind: "valid"; name: string }
  | { kind: "empty" }
  | { kind: "duplicate" };

export function clientNameMessage(v: ClientNameValidation): string | null {
  switch (v.kind) {
    case "valid":
      return null;
    case "empty":
      return "Enter a client name.";
    case "duplicate":
      return "A client with this name already exists.";
  }
}

function clientNameKey(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .trim()
    .toLowerCase();
}

export function validateClientName(raw: string, existingNames: string[]): ClientNameValidation {
  const name = trimmed(raw, Limits.maxClientNameLength);
  if (name === "") return { kind: "empty" };
  const key = clientNameKey(name);
  const duplicate = existingNames.some((n) => clientNameKey(n) === key);
  return duplicate ? { kind: "duplicate" } : { kind: "valid", name };
}
