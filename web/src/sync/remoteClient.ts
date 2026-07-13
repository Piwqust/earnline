import type {
  ClientRow,
  EntryRow,
  HeadingRow,
  TombstoneRow,
  WorkspaceProfilePayload,
  WorkspaceProfileRow,
} from "./remoteRecords";

export type RowTable = "earnline_clients" | "earnline_entries" | "earnline_headings" | "earnline_tombstones";
export type CursorColumn = "updated_at" | "deleted_at";

export interface RowByTable {
  earnline_clients: ClientRow;
  earnline_entries: EntryRow;
  earnline_headings: HeadingRow;
  earnline_tombstones: TombstoneRow;
}

export type RemoteConnectionStatus = "connecting" | "connected" | "polling" | "disconnected" | "error";

export interface RemoteValidation {
  /** Opaque, server-derived identifier. Never the raw workspace id. */
  scope: string;
  transport: "proxy" | "direct";
}

export interface SyncRemote {
  readonly rowWorkspace: string;
  readonly transport: "proxy" | "direct";
  validate(signal?: AbortSignal): Promise<RemoteValidation>;
  fetchProfile(signal?: AbortSignal): Promise<WorkspaceProfileRow | null>;
  upsertProfile(payload: WorkspaceProfilePayload, signal?: AbortSignal): Promise<WorkspaceProfileRow>;
  fetchPage<T extends RowTable>(
    table: T,
    cursorColumn: CursorColumn,
    sinceMs: number | null,
    from: number,
    limit: number,
    signal?: AbortSignal,
  ): Promise<RowByTable[T][]>;
  upsertRows<T extends RowTable>(table: T, rows: RowByTable[T][], signal?: AbortSignal): Promise<void>;
  deleteRows(table: Exclude<RowTable, "earnline_tombstones">, ids: string[], signal?: AbortSignal): Promise<void>;
  subscribe?(
    onChange: () => void,
    onStatus: (status: RemoteConnectionStatus, error?: string) => void,
  ): () => void;
}

export class RemoteRequestError extends Error {
  readonly status: number | null;

  constructor(message: string, status: number | null = null) {
    super(message);
    this.name = "RemoteRequestError";
    this.status = status;
  }
}
