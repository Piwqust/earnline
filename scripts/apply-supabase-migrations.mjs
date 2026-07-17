import { readFile } from "node:fs/promises";
import { basename } from "node:path";

const projectRef = (process.env.SUPABASE_PROJECT_REF ?? "").trim();
const managementToken = (process.env.SUPABASE_ACCESS_TOKEN ?? "").trim();
const files = process.argv.slice(2);
if (!projectRef || !managementToken || files.length === 0) {
  throw new Error("Set SUPABASE_PROJECT_REF and SUPABASE_ACCESS_TOKEN, then pass one or more migration files.");
}

async function query(path, sql) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/database/query${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${managementToken}`, "content-type": "application/json" },
    body: JSON.stringify({ query: sql }),
    signal: AbortSignal.timeout(120_000),
  });
  const text = await response.text();
  const value = text ? JSON.parse(text) : null;
  if (!response.ok) throw new Error(`Management API returned HTTP ${response.status}: ${value?.message ?? value?.error ?? "query failed"}`);
  return value;
}

function literal(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

for (const file of files) {
  const match = basename(file).match(/^(\d{14})_([a-z0-9_]+)\.sql$/);
  if (!match) throw new Error(`Invalid migration filename: ${file}`);
  const [, version, name] = match;
  const existing = await query("/read-only", `
    select version from supabase_migrations.schema_migrations
    where version = ${literal(version)}
  `);
  if (existing.length > 0) {
    console.log(`Already applied: ${version}_${name}`);
    continue;
  }

  const sql = await readFile(file, "utf8");
  if (sql.includes("$earnline_migration$")) throw new Error(`${file} contains the reserved migration delimiter.`);
  await query("", `
    begin;
    ${sql}
    insert into supabase_migrations.schema_migrations (version, name, statements)
    values (
      ${literal(version)},
      ${literal(name)},
      array[$earnline_migration$${sql}$earnline_migration$]::text[]
    );
    commit;
  `);
  console.log(`Applied: ${version}_${name}`);
}
