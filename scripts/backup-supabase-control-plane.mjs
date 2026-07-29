import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const projectRef = (process.env.SUPABASE_PROJECT_REF ?? "").trim();
const projectURL = (process.env.SUPABASE_URL ?? "").trim();
const serviceRoleKey = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? "").trim();
const managementToken = (process.env.SUPABASE_ACCESS_TOKEN ?? "").trim();
if (![projectRef, projectURL, serviceRoleKey, managementToken].every(Boolean)) {
  throw new Error("Set SUPABASE_PROJECT_REF, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and SUPABASE_ACCESS_TOKEN.");
}

const stamp = new Date().toISOString().replaceAll(":", "-").replace(/\.\d{3}Z$/, "Z");
const output = join(process.cwd(), ".local-backups", `supabase-control-plane-${stamp}`);
await mkdir(output, { recursive: true, mode: 0o700 });

async function request(url, init = {}, attempts = 3) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const response = await fetch(url, { ...init, signal: AbortSignal.timeout(60_000) });
      const text = await response.text();
      const value = text ? JSON.parse(text) : null;
      if (!response.ok) throw new Error(`${new URL(url).pathname} returned HTTP ${response.status}`);
      return value;
    } catch (error) {
      lastError = error;
      if (attempt === attempts) throw error;
      await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
    }
  }
  throw lastError;
}

const managementHeaders = { authorization: `Bearer ${managementToken}` };
async function management(path) {
  return request(`https://api.supabase.com/v1/projects/${projectRef}${path}`, { headers: managementHeaders });
}

async function query(sql) {
  return request(`https://api.supabase.com/v1/projects/${projectRef}/database/query/read-only`, {
    method: "POST",
    headers: { ...managementHeaders, "content-type": "application/json" },
    body: JSON.stringify({ query: sql }),
  });
}

async function listAuthUsers() {
  const users = [];
  for (let page = 1; ; page += 1) {
    const url = new URL("/auth/v1/admin/users", projectURL);
    url.searchParams.set("page", String(page));
    url.searchParams.set("per_page", "1000");
    const value = await request(url, {
      headers: { apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}` },
    });
    const batch = value?.users ?? [];
    users.push(...batch);
    if (batch.length < 1000) return users;
  }
}

const snapshots = {
  "auth-users.json": await listAuthUsers(),
  "auth-config.json": await management("/config/auth"),
  "platform-backups.json": await management("/database/backups"),
  "migration-history.json": await management("/database/migrations"),
  "database-summary.json": await query(`
    select current_database() as database_name,
           pg_database_size(current_database()) as database_bytes,
           current_setting('server_version') as postgres_version
  `),
  "schema-columns.json": await query(`
    select table_schema, table_name, ordinal_position, column_name, data_type,
           is_nullable, column_default
    from information_schema.columns
    where table_schema in ('public', 'auth')
    order by table_schema, table_name, ordinal_position
  `),
  "schema-policies.json": await query(`
    select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    from pg_policies
    where schemaname = 'public'
    order by tablename, policyname
  `),
  "schema-functions.json": await query(`
    select n.nspname as schema_name, p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as arguments,
           pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'earnline_%'
    order by p.proname, arguments
  `),
  "schema-triggers.json": await query(`
    select event_object_schema, event_object_table, trigger_name,
           event_manipulation, action_timing, action_statement
    from information_schema.triggers
    where event_object_schema = 'public'
    order by event_object_table, trigger_name, event_manipulation
  `),
  "schema-grants.json": await query(`
    select table_schema, table_name, grantee, privilege_type
    from information_schema.role_table_grants
    where table_schema = 'public' and table_name like 'earnline_%'
    order by table_name, grantee, privilege_type
  `),
  "table-counts.json": await query(`
    select 'earnline_clients' as table_name, count(*) as rows from public.earnline_clients
    union all select 'earnline_entries', count(*) from public.earnline_entries
    union all select 'earnline_headings', count(*) from public.earnline_headings
    union all select 'earnline_tombstones', count(*) from public.earnline_tombstones
    union all select 'earnline_profiles', count(*) from public.earnline_profiles
    union all select 'earnline_project_icons', count(*) from public.earnline_project_icons
    union all select 'earnline_month_reviews', count(*) from public.earnline_month_reviews
    order by table_name
  `),
};

const manifest = {
  createdAt: new Date().toISOString(),
  projectRef,
  kind: "control-plane-and-schema-metadata",
  warning: "Sensitive local backup. Keep outside source control. Restore still requires a platform backup or pg_dump.",
  files: {},
};

for (const [name, value] of Object.entries(snapshots)) {
  const serialized = `${JSON.stringify(value, null, 2)}\n`;
  await writeFile(join(output, name), serialized, { mode: 0o600 });
  manifest.files[name] = {
    bytes: Buffer.byteLength(serialized),
    sha256: createHash("sha256").update(serialized).digest("hex"),
  };
}
await writeFile(join(output, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });

console.log(`Control-plane backup complete: ${output}`);
console.log(`Auth users: ${snapshots["auth-users.json"].length}`);
console.log(`Migration records: ${snapshots["migration-history.json"].length ?? 0}`);
