import {
  decodeClientRows,
  decodeEntryRows,
  decodeHeadingRows,
  decodeTombstoneRows,
  decodeWorkspaceProfile,
  type WorkspaceProfilePayload,
} from "./remoteRecords";
import {
  RemoteRequestError,
  type CursorColumn,
  type RemoteValidation,
  type RowByTable,
  type RowTable,
  type SyncRemote,
} from "./remoteClient";

interface ProxyResponse {
  data?: unknown;
  error?: string;
}

function normalizeEndpoint(value: string): string {
  const parsed = new URL(value.trim());
  if (parsed.protocol !== "https:" && !(import.meta.env.DEV && parsed.protocol === "http:")) {
    throw new Error("The sync endpoint must use HTTPS.");
  }
  return parsed.toString().replace(/\/$/, "");
}

async function endpointBoundScope(endpoint: string, remoteScope: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`earnline-proxy:${endpoint}:${remoteScope}`),
  );
  return [...new Uint8Array(digest)]
    .slice(0, 16)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export class ProxyRemote implements SyncRemote {
  readonly transport = "proxy" as const;
  readonly rowWorkspace = "proxy";
  private readonly endpoint: string;
  private readonly capability: string;

  constructor(endpoint: string, capability: string) {
    this.endpoint = normalizeEndpoint(endpoint);
    this.capability = capability.trim();
    if (this.capability.length < 24) throw new Error("The connection code is incomplete.");
  }

  private async request(action: string, payload: Record<string, unknown> = {}, signal?: AbortSignal): Promise<unknown> {
    let response: Response;
    try {
      response = await fetch(this.endpoint, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-earnline-capability": this.capability,
        },
        body: JSON.stringify({ action, ...payload }),
        cache: "no-store",
        credentials: "omit",
        referrerPolicy: "no-referrer",
        signal,
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") throw error;
      throw new RemoteRequestError("Could not reach the Earnline sync service.");
    }
    const json = (await response.json().catch(() => ({}))) as ProxyResponse;
    if (!response.ok) {
      const safeMessage = response.status === 401 || response.status === 403
        ? "The connection code was rejected."
        : json.error || `Sync service returned ${response.status}.`;
      throw new RemoteRequestError(safeMessage, response.status);
    }
    return json.data;
  }

  async validate(signal?: AbortSignal): Promise<RemoteValidation> {
    const value = await this.request("validate", {}, signal);
    if (!value || typeof value !== "object" || !("scope" in value) ||
      typeof value.scope !== "string" || value.scope.length < 16 || value.scope.length > 256) {
      throw new RemoteRequestError("The sync service returned an invalid validation response.");
    }
    return { scope: await endpointBoundScope(this.endpoint, value.scope), transport: "proxy" };
  }

  async fetchProfile(signal?: AbortSignal) {
    const value = await this.request("profile.get", {}, signal);
    return value == null ? null : decodeWorkspaceProfile(value);
  }

  async upsertProfile(payload: WorkspaceProfilePayload, signal?: AbortSignal) {
    return decodeWorkspaceProfile(await this.request("profile.upsert", { row: payload }, signal));
  }

  async fetchPage<T extends RowTable>(
    table: T,
    cursorColumn: CursorColumn,
    sinceMs: number | null,
    from: number,
    limit: number,
    signal?: AbortSignal,
  ): Promise<RowByTable[T][]> {
    const value = await this.request("rows.list", { table, cursorColumn, sinceMs, from, limit }, signal);
    switch (table) {
      case "earnline_clients":
        return decodeClientRows(value) as RowByTable[T][];
      case "earnline_entries":
        return decodeEntryRows(value) as RowByTable[T][];
      case "earnline_headings":
        return decodeHeadingRows(value) as RowByTable[T][];
      case "earnline_tombstones":
        return decodeTombstoneRows(value) as RowByTable[T][];
    }
  }

  async upsertRows<T extends RowTable>(
    table: T,
    rows: RowByTable[T][],
    signal?: AbortSignal,
  ): Promise<void> {
    await this.request("rows.upsert", { table, rows }, signal);
  }

  async deleteRows(
    table: Exclude<RowTable, "earnline_tombstones">,
    ids: string[],
    signal?: AbortSignal,
  ): Promise<void> {
    await this.request("rows.delete", { table, ids }, signal);
  }
}
