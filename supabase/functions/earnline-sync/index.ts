import { withSupabase } from "npm:@supabase/server@^1";

type TableName = "earnline_clients" | "earnline_entries" | "earnline_headings" | "earnline_project_icons" | "earnline_tombstones";
type CursorColumn = "updated_at" | "deleted_at";

const TABLE_COLUMNS: Record<TableName, readonly string[]> = {
  earnline_clients: ["id", "name", "color_hex", "sort_index", "created_at", "updated_at"],
  earnline_entries: ["id", "client_id", "amount", "currency_code", "project", "task", "date", "hold_until", "status", "sort_index", "created_at", "updated_at"],
  earnline_headings: ["id", "title", "date", "sort_index", "created_at", "updated_at"],
  earnline_project_icons: ["id", "project_key", "symbol_name", "created_at", "updated_at"],
  earnline_tombstones: ["id", "entity", "record_id", "deleted_at", "created_at"],
};
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

function capabilityHashes(): string[] {
  const configured = Deno.env.get("EARNLINE_WEB_CAPABILITY_HASHES")?.trim()
    || Deno.env.get("EARNLINE_WEB_CAPABILITY_SHA256")?.trim()
    || "";
  const hashes = configured.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean);
  if (hashes.length === 0 || hashes.some((value) => !/^[a-f0-9]{64}$/.test(value))) {
    throw new Error("Server capability hashes are not configured correctly.");
  }
  return hashes;
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

function constantTimeEqual(left: string, right: string): boolean {
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (a[index % Math.max(a.length, 1)] ?? 0) ^ (b[index % Math.max(b.length, 1)] ?? 0);
  }
  return difference === 0;
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

const capabilityHandler = withSupabase({ auth: "none" }, async (request, context) => {
    if (!originAllowed(request)) return failure("Origin is not allowed.", 403);
    if (request.method !== "POST") return failure("Method not allowed.", 405);

    const supplied = request.headers.get("x-earnline-capability") ?? "";
    const expectedHashes = capabilityHashes();
    const suppliedHash = await sha256(supplied);
    const accepted = expectedHashes.reduce((match, expected) => constantTimeEqual(suppliedHash, expected) || match, false);
    if (!accepted) return failure("Connection code rejected.", 401);

    const workspaceId = env("EARNLINE_WORKSPACE_ID");
    const scope = (await sha256(`earnline:${workspaceId}:${env("EARNLINE_SCOPE_SALT")}`)).slice(0, 32);
    const admin = context.supabaseAdmin;
    if (!admin) return failure("Sync service is not configured.", 503);

    try {
      const body = record(await request.json());
      const action = body.action;
      if (action === "validate") return response({ scope, transport: "proxy" });

      if (action === "profile.get") {
        const { data, error } = await admin.from("earnline_profiles").select(PROFILE_COLUMNS.join(","))
          .eq("workspace_id", workspaceId).limit(1);
        if (error) throw error;
        return response(data?.[0] ? hideWorkspace(data[0], scope) : null);
      }
      if (action === "profile.upsert") {
        const row = profileRow(body.row, workspaceId);
        const { data, error } = await admin.from("earnline_profiles").upsert(row, { onConflict: "workspace_id" })
          .select(PROFILE_COLUMNS.join(",")).single();
        if (error) throw error;
        return response(hideWorkspace(data, scope));
      }
      if (action === "rows.list") {
        const table = tableName(body.table);
        const expectedCursor: CursorColumn = table === "earnline_tombstones" ? "deleted_at" : "updated_at";
        if (body.cursorColumn !== expectedCursor) throw new Error("Invalid cursor column.");
        const from = typeof body.from === "number" && Number.isSafeInteger(body.from) && body.from >= 0 ? body.from : 0;
        const limit = typeof body.limit === "number" && Number.isSafeInteger(body.limit) && body.limit > 0 && body.limit <= 1000 ? body.limit : 1000;
        const columns = ["workspace_id", ...TABLE_COLUMNS[table]].join(",");
        let query = admin.from(table).select(columns).eq("workspace_id", workspaceId)
          .order(expectedCursor, { ascending: true }).order("id", { ascending: true });
        if (typeof body.sinceMs === "number" && Number.isFinite(body.sinceMs)) {
          query = query.gte(expectedCursor, new Date(body.sinceMs).toISOString());
        } else if (body.sinceMs !== null) {
          throw new Error("Invalid sync cursor.");
        }
        const { data, error } = await query.range(from, from + limit - 1);
        if (error) throw error;
        return response(hideWorkspace(data ?? [], scope));
      }
      if (action === "rows.upsert") {
        const table = tableName(body.table);
        const rows = scopedRows(body.rows, table, workspaceId);
        const { error } = await admin.from(table).upsert(rows);
        if (error) throw error;
        return response({ ok: true });
      }
      if (action === "rows.delete") {
        const table = tableName(body.table);
        if (table === "earnline_tombstones") throw new Error("Tombstones are append-only.");
        if (table === "earnline_project_icons") throw new Error("Project icons reset through upsert, not delete.");
        const recordIds = ids(body.ids);
        if (recordIds.length > 0) {
          const { error } = await admin.from(table).delete().eq("workspace_id", workspaceId).in("id", recordIds);
          if (error) throw error;
        }
        return response({ ok: true });
      }
      return failure("Unknown sync action.", 400);
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
  headers.set("access-control-allow-headers", "content-type, x-earnline-capability");
  headers.set("access-control-allow-methods", "POST, OPTIONS");
  headers.append("vary", "Origin");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export default {
  async fetch(request: Request): Promise<Response> {
    try {
      if (!originAllowed(request)) return withCors(request, failure("Origin is not allowed.", 403));
      if (request.method === "OPTIONS") return withCors(request, response({ ok: true }));
      return withCors(request, await capabilityHandler(request));
    } catch {
      return failure("Sync service is not configured.", 503);
    }
  },
};
