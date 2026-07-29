import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const projectURL = (process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL ?? "").trim();
const publishableKey = (process.env.SUPABASE_PUBLISHABLE_KEY ?? process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "").trim();
const backupAccessToken = (process.env.SUPABASE_BACKUP_ACCESS_TOKEN ?? process.env.SUPABASE_BACKUP_SERVICE_ROLE_KEY ?? "").trim();
if (!projectURL || !publishableKey || !backupAccessToken) {
  throw new Error("Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, and a server-only SUPABASE_BACKUP_ACCESS_TOKEN.");
}

const defaultTables = [
  "earnline_clients",
  "earnline_entries",
  "earnline_headings",
  "earnline_tombstones",
  "earnline_profiles",
  "earnline_project_icons",
  "earnline_month_reviews",
];
const tables = (process.env.SUPABASE_BACKUP_TABLES ?? "")
  .split(",")
  .map((table) => table.trim())
  .filter(Boolean);
if (tables.length === 0) tables.push(...defaultTables);
if (tables.some((table) => !/^earnline_[a-z_]+$/.test(table))) {
  throw new Error("SUPABASE_BACKUP_TABLES contains an invalid table name.");
}
const pageSize = 250;
const stamp = new Date().toISOString().replaceAll(":", "-").replace(/\.\d{3}Z$/, "Z");
const output = join(process.cwd(), ".local-backups", `supabase-rest-${stamp}`);
await mkdir(output, { recursive: true, mode: 0o700 });

const manifest = {
  createdAt: new Date().toISOString(),
  kind: "rest-data-only",
  warning: "This is an emergency row export, not a replacement for pg_dump or Supabase backups.",
  tables: {},
};

for (const table of tables) {
  const rows = [];
  for (let from = 0; ; from += pageSize) {
    const url = new URL(`/rest/v1/${table}`, projectURL);
    url.searchParams.set("select", "*");
    url.searchParams.set("limit", String(pageSize));
    url.searchParams.set("offset", String(from));
    url.searchParams.set("order", "id.asc");
    let response;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        response = await fetch(url, {
          headers: {
            apikey: publishableKey,
            // The public key intentionally remains only the API key. Reading
            // every workspace row requires a separately supplied backup role.
            authorization: `Bearer ${backupAccessToken}`,
            connection: "close",
          },
          signal: AbortSignal.timeout(60_000),
        });
        break;
      } catch (error) {
        if (attempt === 3) {
          throw new Error(`Could not export ${table} after ${attempt} attempts.`, { cause: error });
        }
      }
    }
    if (!response) throw new Error(`Could not export ${table}: no response`);
    if (!response.ok) throw new Error(`Could not export ${table}: HTTP ${response.status}`);
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`Could not export ${table}: invalid response`);
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  const serialized = `${JSON.stringify(rows, null, 2)}\n`;
  await writeFile(join(output, `${table}.json`), serialized, { mode: 0o600 });
  manifest.tables[table] = {
    rows: rows.length,
    sha256: createHash("sha256").update(serialized).digest("hex"),
  };
}

await writeFile(join(output, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });
console.log(`REST backup complete: ${output}`);
for (const [table, details] of Object.entries(manifest.tables)) console.log(`${table}: ${details.rows} rows`);
