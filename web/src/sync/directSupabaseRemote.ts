import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { getSupabase } from "./supabaseClient";
import {
  decodeClientRows,
  decodeEntryRows,
  decodeHeadingRows,
  decodeMonthReviewRows,
  decodeTombstoneRows,
  decodeWorkspaceProfile,
  type WorkspaceProfilePayload,
} from "./remoteRecords";
import type {
  CursorColumn,
  RemoteConnectionStatus,
  RemoteValidation,
  RowByTable,
  RowTable,
  SyncRemote,
} from "./remoteClient";

const REALTIME_TABLES: RowTable[] = [
  "earnline_clients",
  "earnline_entries",
  "earnline_headings",
  "earnline_month_reviews",
  "earnline_tombstones",
];

async function opaqueScope(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Explicit local-development escape hatch. Production must use ProxyRemote. */
export class DirectSupabaseRemote implements SyncRemote {
  readonly transport = "direct" as const;
  readonly rowWorkspace: string;
  private readonly supabase: SupabaseClient;
  private readonly url: string;

  constructor(url: string, key: string, workspaceId: string) {
    if (!import.meta.env.DEV) throw new Error("Direct Supabase sync is disabled in production builds.");
    this.url = url.trim();
    this.rowWorkspace = workspaceId.trim();
    this.supabase = getSupabase(this.url, key.trim());
  }

  async validate(signal?: AbortSignal): Promise<RemoteValidation> {
    const result = await this.supabase
      .from("earnline_profiles")
      .select("workspace_id")
      .eq("workspace_id", this.rowWorkspace)
      .limit(1)
      .abortSignal(signal ?? new AbortController().signal);
    if (result.error) throw result.error;
    return { scope: await opaqueScope(`${new URL(this.url).origin}|${this.rowWorkspace}`), transport: "direct" };
  }

  async fetchProfile(signal?: AbortSignal) {
    const result = await this.supabase
      .from("earnline_profiles")
      .select("workspace_id,base_currency_code,secondary_currency_code,exchange_rate,updated_at")
      .eq("workspace_id", this.rowWorkspace)
      .limit(1)
      .abortSignal(signal ?? new AbortController().signal);
    if (result.error) throw result.error;
    return result.data?.[0] == null ? null : decodeWorkspaceProfile(result.data[0]);
  }

  async upsertProfile(payload: WorkspaceProfilePayload, signal?: AbortSignal) {
    const result = await this.supabase
      .from("earnline_profiles")
      .upsert({ ...payload, workspace_id: this.rowWorkspace }, { onConflict: "workspace_id" })
      .select("workspace_id,base_currency_code,secondary_currency_code,exchange_rate,updated_at")
      .abortSignal(signal ?? new AbortController().signal)
      .single();
    if (result.error) throw result.error;
    return decodeWorkspaceProfile(result.data);
  }

  async fetchPage<T extends RowTable>(
    table: T,
    cursorColumn: CursorColumn,
    sinceMs: number | null,
    from: number,
    limit: number,
    signal?: AbortSignal,
  ): Promise<RowByTable[T][]> {
    let query = this.supabase
      .from(table)
      .select("*")
      .eq("workspace_id", this.rowWorkspace)
      .order(cursorColumn, { ascending: true })
      .order("id", { ascending: true });
    if (sinceMs != null) query = query.gte(cursorColumn, new Date(sinceMs).toISOString());
    const result = await query.range(from, from + limit - 1).abortSignal(signal ?? new AbortController().signal);
    if (result.error) throw result.error;
    switch (table) {
      case "earnline_clients": return decodeClientRows(result.data) as RowByTable[T][];
      case "earnline_entries": return decodeEntryRows(result.data) as RowByTable[T][];
      case "earnline_headings": return decodeHeadingRows(result.data) as RowByTable[T][];
      case "earnline_month_reviews": return decodeMonthReviewRows(result.data) as RowByTable[T][];
      case "earnline_tombstones": return decodeTombstoneRows(result.data) as RowByTable[T][];
    }
  }

  async upsertRows<T extends RowTable>(table: T, rows: RowByTable[T][], signal?: AbortSignal): Promise<void> {
    const scoped = rows.map((row) => ({ ...row, workspace_id: this.rowWorkspace }));
    const result = await this.supabase.from(table).upsert(scoped).abortSignal(signal ?? new AbortController().signal);
    if (result.error) throw result.error;
  }

  async deleteRows(
    table: Exclude<RowTable, "earnline_tombstones" | "earnline_month_reviews">,
    ids: string[],
    signal?: AbortSignal,
  ): Promise<void> {
    const result = await this.supabase
      .from(table)
      .delete()
      .in("id", ids)
      .eq("workspace_id", this.rowWorkspace)
      .abortSignal(signal ?? new AbortController().signal);
    if (result.error) throw result.error;
  }

  subscribe(
    onChange: () => void,
    onStatus: (status: RemoteConnectionStatus, error?: string) => void,
  ): () => void {
    let channel: RealtimeChannel = this.supabase.channel(`earnline-dev-sync:${this.rowWorkspace}`);
    for (const table of REALTIME_TABLES) {
      channel = channel.on(
        "postgres_changes",
        { event: "*", schema: "public", table, filter: `workspace_id=eq.${this.rowWorkspace}` },
        onChange,
      );
    }
    channel = channel.on(
      "postgres_changes",
      { event: "*", schema: "public", table: "earnline_profiles", filter: `workspace_id=eq.${this.rowWorkspace}` },
      onChange,
    );
    channel.subscribe((state, error) => {
      if (state === "SUBSCRIBED") onStatus("connected");
      else if (state === "CHANNEL_ERROR" || state === "TIMED_OUT") onStatus("error", error?.message);
      else if (state === "CLOSED") onStatus("disconnected");
      else onStatus("connecting");
    });
    return () => { void this.supabase.removeChannel(channel); };
  }
}
