import { withSupabase } from "npm:@supabase/server@^1";
import type { SupabaseClient } from "npm:@supabase/supabase-js@^2";

type TableName = "earnline_clients" | "earnline_entries" | "earnline_headings" | "earnline_project_icons" | "earnline_month_reviews" | "earnline_tombstones";
type CursorColumn = "updated_at" | "deleted_at";

const TABLE_COLUMNS: Record<TableName, readonly string[]> = {
  earnline_clients: ["id", "name", "color_hex", "sort_index", "created_at", "updated_at"],
  earnline_entries: ["id", "client_id", "amount", "currency_code", "project", "task", "date", "hold_until", "status", "sort_index", "created_at", "updated_at"],
  earnline_headings: ["id", "title", "date", "sort_index", "created_at", "updated_at"],
  earnline_project_icons: ["id", "project_key", "symbol_name", "created_at", "updated_at"],
  earnline_month_reviews: ["id", "month_start", "note", "closed_at", "created_at", "updated_at"],
  earnline_tombstones: ["id", "entity", "record_id", "deleted_at", "created_at"],
};
const MONTH_REVIEW_MAX_NOTE_LENGTH = 280;
const PROJECT_SYMBOLS = new Set([
  "folder", "briefcase", "display", "paintpalette", "camera", "video",
  "music.note", "doc.text", "megaphone", "cart", "globe",
  "wrench.and.screwdriver", "shippingbox", "sparkles",
  "chart.line.uptrend.xyaxis", "building.2",
]);
const PROFILE_COLUMNS = ["workspace_id", "base_currency_code", "secondary_currency_code", "exchange_rate", "updated_at"] as const;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const encoder = new TextEncoder();

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Server secret ${name} is not configured.`);
  return value;
}

function originAllowed(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return true;
  const allowed = env("EARNLINE_ALLOWED_ORIGINS").split(",").map((value) => new URL(value.trim()).origin);
  return allowed.includes(origin);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function response(data: unknown, status = 200): Response {
  return Response.json({ data }, {
    status,
    headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" },
  });
}

function failure(message: string, status: number): Response {
  return Response.json({ error: message }, {
    status,
    headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" },
  });
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Request body must be an object.");
  return value as Record<string, unknown>;
}

function tableName(value: unknown): TableName {
  if (typeof value !== "string" || !Object.hasOwn(TABLE_COLUMNS, value)) throw new Error("Unsupported sync table.");
  return value as TableName;
}

function ids(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 1000 ||
    value.some((item) => typeof item !== "string" || !UUID_PATTERN.test(item))) {
    throw new Error("Invalid record id list.");
  }
  return [...new Set(value)];
}

function normalizedProjectKey(value: string): string {
  return value.trim().split(/\s+/u).join(" ").normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();
}

function isMonthStart(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^(\d{4})-(\d{2})-01$/.exec(value);
  if (!match) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime())
    && parsed.getUTCFullYear() === Number(match[1])
    && parsed.getUTCMonth() + 1 === Number(match[2])
    && parsed.getUTCDate() === 1;
}

function isTimestamp(value: unknown): value is string {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T/.test(value)
    && Number.isFinite(Date.parse(value));
}

function scopedRows(value: unknown, table: TableName, workspaceId: string): Record<string, unknown>[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 1000) throw new Error("Invalid sync row batch.");
  const allowed = new Set(TABLE_COLUMNS[table]);
  return value.map((item) => {
    const input = record(item);
    const output: Record<string, unknown> = { workspace_id: workspaceId };
    for (const [key, field] of Object.entries(input)) {
      if (allowed.has(key)) output[key] = field;
    }
    if (typeof output.id !== "string" || !UUID_PATTERN.test(output.id)) {
      throw new Error("Every sync row requires a UUID id.");
    }
    if (table === "earnline_entries" &&
      (typeof output.client_id !== "string" || !UUID_PATTERN.test(output.client_id))) {
      throw new Error("Every entry requires a UUID client id.");
    }
    if (table === "earnline_project_icons" &&
      (typeof output.project_key !== "string" || output.project_key.length < 1 || output.project_key.length > 40 ||
        output.project_key !== normalizedProjectKey(output.project_key) ||
        typeof output.symbol_name !== "string" || !PROJECT_SYMBOLS.has(output.symbol_name))) {
      throw new Error("Every project icon requires a normalized project key and supported symbol.");
    }
    if (table === "earnline_month_reviews" &&
      (!isMonthStart(output.month_start) || typeof output.note !== "string" ||
        Array.from(output.note).length > MONTH_REVIEW_MAX_NOTE_LENGTH ||
        !Object.hasOwn(output, "closed_at") ||
        (output.closed_at !== null && output.closed_at !== undefined && !isTimestamp(output.closed_at)))) {
      throw new Error("Every month review requires a month start, short note, and valid close timestamp.");
    }
    if (table === "earnline_tombstones") {
      if (typeof output.record_id !== "string" || !UUID_PATTERN.test(output.record_id)) {
        throw new Error("Every tombstone requires a UUID record id.");
      }
      if (output.entity !== "client" && output.entity !== "entry" && output.entity !== "heading") {
        throw new Error("Every tombstone requires a supported entity.");
      }
    }
    return output;
  });
}

function profileRow(value: unknown, workspaceId: string): Record<string, unknown> {
  const input = record(value);
  const base = input.base_currency_code;
  const secondary = input.secondary_currency_code;
  const rate = input.exchange_rate;
  if (typeof base !== "string" || typeof secondary !== "string" ||
    !/^[A-Z]{3,16}$/.test(base) || !/^[A-Z]{3,16}$/.test(secondary) || base === secondary) {
    throw new Error("Invalid workspace currency profile.");
  }
  const numericRate = typeof rate === "number" ? rate : typeof rate === "string" ? Number(rate) : Number.NaN;
  if (!Number.isFinite(numericRate) || numericRate <= 0 || numericRate > 1_000_000_000) {
    throw new Error("Invalid workspace exchange rate.");
  }
  return {
    workspace_id: workspaceId,
    base_currency_code: base,
    secondary_currency_code: secondary,
    exchange_rate: String(rate),
  };
}

function hideWorkspace(value: unknown, scope: string): unknown {
  if (Array.isArray(value)) return value.map((row) => hideWorkspace(row, scope));
  if (value && typeof value === "object") return { ...(value as Record<string, unknown>), workspace_id: scope };
  return value;
}

async function executeAction(
  body: Record<string, unknown>,
  userClient: SupabaseClient<any>,
  workspaceId: string,
  scope: string,
): Promise<unknown> {
  const action = body.action;
  if (action === "validate") return { scope, transport: "proxy" };

  if (action === "profile.get") {
    const { data, error } = await userClient.from("earnline_profiles").select(PROFILE_COLUMNS.join(","))
      .eq("workspace_id", workspaceId).limit(1);
    if (error) throw error;
    return data?.[0] ? hideWorkspace(data[0], scope) : null;
  }
  if (action === "profile.upsert") {
    const row = profileRow(body.row, workspaceId);
    const { data, error } = await userClient.from("earnline_profiles").upsert(row, { onConflict: "workspace_id" })
      .select(PROFILE_COLUMNS.join(",")).single();
    if (error) throw error;
    return hideWorkspace(data, scope);
  }
  if (action === "rows.list") {
    const table = tableName(body.table);
    const expectedCursor: CursorColumn = table === "earnline_tombstones" ? "deleted_at" : "updated_at";
    if (body.cursorColumn !== expectedCursor) throw new Error("Invalid cursor column.");
    const from = typeof body.from === "number" && Number.isSafeInteger(body.from) && body.from >= 0 ? body.from : 0;
    const limit = typeof body.limit === "number" && Number.isSafeInteger(body.limit) && body.limit > 0 && body.limit <= 1000 ? body.limit : 1000;
    const columns = ["workspace_id", ...TABLE_COLUMNS[table]].join(",");
    let query = userClient.from(table).select(columns).eq("workspace_id", workspaceId)
      .order(expectedCursor, { ascending: true }).order("id", { ascending: true });
    if (typeof body.sinceMs === "number" && Number.isFinite(body.sinceMs)) {
      query = query.gte(expectedCursor, new Date(body.sinceMs).toISOString());
    } else if (body.sinceMs !== null) {
      throw new Error("Invalid sync cursor.");
    }
    const { data, error } = await query.range(from, from + limit - 1);
    if (error) throw error;
    return hideWorkspace(data ?? [], scope);
  }
  if (action === "rows.upsert") {
    const table = tableName(body.table);
    const rows = scopedRows(body.rows, table, workspaceId);
    const { error } = await userClient.from(table).upsert(rows);
    if (error) throw error;
    return { ok: true };
  }
  if (action === "rows.delete") {
    const table = tableName(body.table);
    if (table === "earnline_tombstones") throw new Error("Tombstones are append-only.");
    if (table === "earnline_project_icons") throw new Error("Project icons reset through upsert, not delete.");
    if (table === "earnline_month_reviews") throw new Error("Month reviews reopen through upsert, not delete.");
    const recordIds = ids(body.ids);
    if (recordIds.length > 0) {
      const { error } = await userClient.from(table).delete().eq("workspace_id", workspaceId).in("id", recordIds);
      if (error) throw error;
    }
    return { ok: true };
  }
  throw new Error("Unknown sync action.");
}

// `verify_jwt = true` in config.toml rejects invalid bearer tokens at the
// platform edge. Every ledger operation intentionally uses the caller-scoped
// client so RLS remains the final tenant boundary. The service-role client is
// never used for user-controlled ids or rows.
const jwtHandler = withSupabase({ auth: "user" }, async (request, context) => {
    if (!originAllowed(request)) return failure("Origin is not allowed.", 403);
    if (request.method !== "POST") return failure("Method not allowed.", 405);

    const userClient = context.supabase as SupabaseClient<any> | undefined;
    if (!userClient) return failure("Sync service is not configured.", 503);

    const callerID = context.userClaims?.id;
    if (typeof callerID !== "string" || callerID.length === 0) {
      return failure("Sign in is required to sync.", 401);
    }

    const { data: memberships, error: membershipError } = await userClient
      .rpc("earnline_current_workspace");
    if (membershipError) {
      console.error("earnline-sync membership lookup failed", membershipError.message);
      return failure("The sync service is not configured.", 503);
    }
    const workspaceId = (Array.isArray(memberships) ? memberships[0] : memberships)?.workspace_id;
    if (typeof workspaceId !== "string" || workspaceId.length === 0) {
      return failure("This account is not paired with a workspace yet.", 403);
    }
    const scope = (await sha256(`earnline:workspace:${workspaceId}:${env("EARNLINE_SCOPE_SALT")}`)).slice(0, 32);

    try {
      const body = record(await request.json());
      if (body.action === "batch") {
        // Not transactional: the actions run in order against the caller-scoped
        // client, so a failure partway through leaves the earlier ones applied
        // and returns one opaque 400. That is survivable only because the sync
        // protocol is idempotent and retried — do not batch anything that is
        // not safe to re-send. See docs/AUDIT-2026-07.md (S2).
        if (!Array.isArray(body.requests) || body.requests.length < 1 || body.requests.length > 12) {
          throw new Error("Invalid sync request batch.");
        }
        const results: unknown[] = [];
        for (const item of body.requests) {
          const nested = record(item);
          if (nested.action === "batch") throw new Error("Nested batches are not supported.");
          results.push(await executeAction(nested, userClient, workspaceId, scope));
        }
        return response(results);
      }
      return response(await executeAction(body, userClient, workspaceId, scope));
    } catch (error) {
      // Detailed database errors stay in server logs; clients receive no schema
      // or identifier details that help probe the workspace.
      console.error("earnline-sync request failed", error instanceof Error ? error.message : "unknown error");
      return failure("The sync request could not be completed.", 400);
    }
});

function withCors(request: Request, response: Response): Response {
  const headers = new Headers(response.headers);
  const origin = request.headers.get("origin");
  if (origin && originAllowed(request)) headers.set("access-control-allow-origin", origin);
  headers.set("access-control-allow-headers", "authorization, content-type");
  headers.set("access-control-allow-methods", "POST, OPTIONS");
  headers.append("vary", "Origin");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export default {
  async fetch(request: Request): Promise<Response> {
    try {
      if (!originAllowed(request)) return withCors(request, failure("Origin is not allowed.", 403));
      if (request.method === "OPTIONS") return withCors(request, response({ ok: true }));
      return withCors(request, await jwtHandler(request));
    } catch {
      return failure("Sync service is not configured.", 503);
    }
  },
};
