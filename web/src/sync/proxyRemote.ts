import {
  decodeClientRows,
  decodeEntryRows,
  decodeHeadingRows,
  decodeMonthReviewRows,
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
import { configuredSupabase } from "./supabaseClient";

interface ProxyResponse {
  data?: unknown;
  error?: string;
}

interface QueuedRequest {
  action: string;
  payload: Record<string, unknown>;
  signal?: AbortSignal;
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
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
  private queue: QueuedRequest[] = [];
  private flushScheduled = false;

  constructor(endpoint: string) {
    this.endpoint = normalizeEndpoint(endpoint);
  }

  private request(action: string, payload: Record<string, unknown> = {}, signal?: AbortSignal): Promise<unknown> {
    return new Promise((resolve, reject) => {
      this.queue.push({ action, payload, signal, resolve, reject });
      if (!this.flushScheduled) {
        this.flushScheduled = true;
        queueMicrotask(() => void this.flush());
      }
    });
  }

  private async flush(): Promise<void> {
    this.flushScheduled = false;
    const pending = this.queue;
    this.queue = [];
    const groups = new Map<AbortSignal | undefined, QueuedRequest[]>();
    for (const item of pending) {
      if (item.signal?.aborted) {
        item.reject(new DOMException("The operation was aborted", "AbortError"));
        continue;
      }
      groups.set(item.signal, [...(groups.get(item.signal) ?? []), item]);
    }
    await Promise.all([...groups.entries()].flatMap(([signal, requests]) => {
      const tasks: Promise<void>[] = [];
      for (let index = 0; index < requests.length; index += 12) {
        tasks.push(this.send(requests.slice(index, index + 12), signal));
      }
      return tasks;
    }));
  }

  private async send(requests: QueuedRequest[], signal?: AbortSignal): Promise<void> {
    const supabase = configuredSupabase();
    if (!supabase) {
      const error = new RemoteRequestError("Supabase browser configuration is missing.");
      requests.forEach((item) => item.reject(error));
      return;
    }
    let session;
    try {
      ({ data: { session } } = await supabase.auth.getSession());
    } catch {
      const error = new RemoteRequestError("Could not read the browser session.", 401);
      requests.forEach((item) => item.reject(error));
      return;
    }
    if (!session?.access_token) {
      const error = new RemoteRequestError("Sign in is required to sync.", 401);
      requests.forEach((item) => item.reject(error));
      return;
    }
    let response: Response;
    try {
      const body = requests.length === 1
        ? { action: requests[0].action, ...requests[0].payload }
        : { action: "batch", requests: requests.map((item) => ({ action: item.action, ...item.payload })) };
      response = await fetch(this.endpoint, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify(body),
        cache: "no-store",
        credentials: "omit",
        referrerPolicy: "no-referrer",
        signal,
      });
    } catch (error) {
      const safeError = error instanceof DOMException && error.name === "AbortError"
        ? error
        : new RemoteRequestError("Could not reach the Earnline sync service.");
      requests.forEach((item) => item.reject(safeError));
      return;
    }
    const json = (await response.json().catch(() => ({}))) as ProxyResponse;
    if (!response.ok) {
      const safeMessage = response.status === 401 || response.status === 403
        ? "This browser is not authorized to sync that workspace."
        : json.error || `Sync service returned ${response.status}.`;
      const error = new RemoteRequestError(safeMessage, response.status);
      requests.forEach((item) => item.reject(error));
      return;
    }
    if (requests.length === 1) {
      requests[0].resolve(json.data);
      return;
    }
    if (!Array.isArray(json.data) || json.data.length !== requests.length) {
      const error = new RemoteRequestError("The sync service returned an invalid batch response.");
      requests.forEach((item) => item.reject(error));
      return;
    }
    requests.forEach((item, index) => item.resolve((json.data as unknown[])[index]));
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
      case "earnline_month_reviews":
        return decodeMonthReviewRows(value) as RowByTable[T][];
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
    table: Exclude<RowTable, "earnline_tombstones" | "earnline_month_reviews">,
    ids: string[],
    signal?: AbortSignal,
  ): Promise<void> {
    await this.request("rows.delete", { table, ids }, signal);
  }
}
