// Deterministic, stable UUIDs — direct port of Util/DeterministicID.swift.
// Uses the same twin-FNV 64-bit hash so a given string maps to the same UUID on
// iOS and web (keeps tombstone + sample-import IDs idempotent across clients).

const MASK = (1n << 64n) - 1n;
const PRIME = 0x100000001b3n;
const SEED_ADD = 0x9e3779b97f4a7c15n;

export function deterministicUuid(value: string): string {
  let h1 = 0xcbf29ce484222325n;
  let h2 = 0x84222325cbf29ce4n;

  const bytes = new TextEncoder().encode(value);
  for (const byte of bytes) {
    const b = BigInt(byte);
    h1 = (h1 ^ b) & MASK;
    h1 = (h1 * PRIME) & MASK;
    h2 = (h2 ^ ((b + SEED_ADD) & MASK)) & MASK;
    h2 = (h2 * PRIME) & MASK;
  }

  const out = new Uint8Array(16);
  for (let i = 0; i < 8; i++) {
    out[i] = Number((h1 >> BigInt((7 - i) * 8)) & 0xffn);
    out[i + 8] = Number((h2 >> BigInt((7 - i) * 8)) & 0xffn);
  }

  out[6] = (out[6] & 0x0f) | 0x50; // version nibble (matches Swift)
  out[8] = (out[8] & 0x3f) | 0x80; // variant

  return formatUuid(out);
}

function formatUuid(b: Uint8Array): string {
  const hex: string[] = [];
  for (const x of b) hex.push(x.toString(16).padStart(2, "0"));
  return (
    hex.slice(0, 4).join("") +
    "-" +
    hex.slice(4, 6).join("") +
    "-" +
    hex.slice(6, 8).join("") +
    "-" +
    hex.slice(8, 10).join("") +
    "-" +
    hex.slice(10, 16).join("")
  );
}

/** Fresh random UUID for new records (mirrors Swift's UUID()). */
export function newUuid(): string {
  return crypto.randomUUID();
}
