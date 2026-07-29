import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve, join } from "node:path";

const backupDirectory = resolve(process.argv[2] ?? "");
const projectURL = (process.env.SUPABASE_RESTORE_URL ?? "").trim();
const publishableKey = (process.env.SUPABASE_RESTORE_PUBLISHABLE_KEY ?? "").trim();
const restoreAccessToken = (process.env.SUPABASE_RESTORE_ACCESS_TOKEN
  ?? process.env.SUPABASE_RESTORE_SERVICE_ROLE_KEY
  ?? "").trim();
if (!process.argv[2] || !projectURL || !publishableKey || !restoreAccessToken) {
  throw new Error(
    "Pass the REST backup directory, then set SUPABASE_RESTORE_URL, SUPABASE_RESTORE_PUBLISHABLE_KEY, and a server-only SUPABASE_RESTORE_ACCESS_TOKEN.",
  );
}

const expectedTables = [
  "earnline_clients",
  "earnline_entries",
  "earnline_headings",
  "earnline_tombstones",
  "earnline_profiles",
  "earnline_project_icons",
  "earnline_month_reviews",
];
const pageSize = 250;

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, stableValue(child)]),
    );
  }
  return value;
}

function canonicalRows(rows) {
  if (!Array.isArray(rows)) throw new Error("A backup table is not a JSON array.");
  const ids = new Set();
  const sorted = rows.map((row) => {
    if (!row || typeof row !== "object" || Array.isArray(row) || typeof row.id !== "string") {
      throw new Error("A backup row has no string id.");
    }
    if (ids.has(row.id)) throw new Error(`A backup contains duplicate id ${row.id}.`);
    ids.add(row.id);
    return stableValue(row);
  }).sort((left, right) => left.id.localeCompare(right.id));
  return JSON.stringify(sorted);
}

function amountToCents(value) {
  const raw = String(value);
  const match = raw.match(/^(-?)(\d+)(?:\.(\d{1,2}))?$/);
  if (!match) throw new Error(`Invalid financial amount in backup: ${raw}`);
  const [, sign, integer, fraction = ""] = match;
  const cents = BigInt(integer) * 100n + BigInt((fraction + "00").slice(0, 2));
  return sign === "-" ? -cents : cents;
}

function totals(rows) {
  const sums = new Map();
  for (const row of rows) {
    if (typeof row.currency_code !== "string") throw new Error("An entry has no currency code.");
    const total = (sums.get(row.currency_code) ?? 0n) + amountToCents(row.amount);
    sums.set(row.currency_code, total);
  }
  return Object.fromEntries([...sums.entries()].sort(([left], [right]) => left.localeCompare(right))
    .map(([currency, cents]) => [currency, cents.toString()]));
}

function verifyForeignKeys(rowsByTable) {
  const clientIDs = new Set(rowsByTable.earnline_clients.map((row) => row.id));
  for (const entry of rowsByTable.earnline_entries) {
    if (typeof entry.client_id !== "string" || !clientIDs.has(entry.client_id)) {
      throw new Error(`Entry ${entry.id} has no client in the restored backup.`);
    }
  }
}

async function fetchRows(table) {
  const rows = [];
  for (let offset = 0; ; offset += pageSize) {
    const url = new URL(`/rest/v1/${table}`, projectURL);
    url.searchParams.set("select", "*");
    url.searchParams.set("limit", String(pageSize));
    url.searchParams.set("offset", String(offset));
    url.searchParams.set("order", "id.asc");
    const response = await fetch(url, {
      headers: {
        apikey: publishableKey,
        authorization: `Bearer ${restoreAccessToken}`,
        connection: "close",
      },
      signal: AbortSignal.timeout(60_000),
    });
    if (!response.ok) throw new Error(`Could not read restored ${table}: HTTP ${response.status}.`);
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`Restored ${table} returned an invalid response.`);
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}

const manifestText = await readFile(join(backupDirectory, "manifest.json"), "utf8");
const manifest = JSON.parse(manifestText);
if (manifest.kind !== "rest-data-only" || !manifest.tables || typeof manifest.tables !== "object") {
  throw new Error("The directory is not an Earnline REST data backup.");
}
if (JSON.stringify(Object.keys(manifest.tables).sort()) !== JSON.stringify(expectedTables)) {
  throw new Error("The backup does not contain the complete current Earnline table set.");
}

const original = {};
for (const table of expectedTables) {
  const serialized = await readFile(join(backupDirectory, `${table}.json`), "utf8");
  const details = manifest.tables[table];
  if (!details || sha256(serialized) !== details.sha256) {
    throw new Error(`Backup integrity check failed for ${table}.`);
  }
  original[table] = JSON.parse(serialized);
  if (original[table].length !== details.rows) {
    throw new Error(`Backup row count is inconsistent for ${table}.`);
  }
}
verifyForeignKeys(original);

const restored = Object.fromEntries(await Promise.all(expectedTables.map(async (table) => [table, await fetchRows(table)])));
verifyForeignKeys(restored);

for (const table of expectedTables) {
  const expectedRows = original[table];
  const restoredRows = restored[table];
  if (expectedRows.length !== restoredRows.length) {
    throw new Error(`Restore mismatch for ${table}: ${expectedRows.length} expected rows, ${restoredRows.length} found.`);
  }
  if (sha256(canonicalRows(expectedRows)) !== sha256(canonicalRows(restoredRows))) {
    throw new Error(`Restore mismatch for ${table}: IDs or row content differ.`);
  }
}

const expectedTotals = totals(original.earnline_entries);
const restoredTotals = totals(restored.earnline_entries);
if (JSON.stringify(expectedTotals) !== JSON.stringify(restoredTotals)) {
  throw new Error("Restore mismatch: financial totals differ.");
}

console.log("Backup restore verification passed.");
for (const table of expectedTables) console.log(`${table}: ${original[table].length} rows`);
console.log(`Financial totals (minor units): ${JSON.stringify(expectedTotals)}`);
