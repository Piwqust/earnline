// Resilient sync orchestration: validated transport, scoped IndexedDB,
// cancellation on reconfigure, exponential retry, multi-tab exclusion and
// coordination, Realtime status in direct dev mode, polling in proxy mode.

import { useSyncExternalStore } from "react";
import {
  activateDatabase,
  getDatabase,
  requestPersistentStorage,
  type EarnlineDB,
} from "../data/db";
import { ProxyRemote } from "../sync/proxyRemote";
import type { RemoteConnectionStatus, SyncRemote } from "../sync/remoteClient";
import { SyncConflictError, sync, syncWorkspaceProfile, type ConflictResolution } from "../sync/syncCoordinator";
import { SyncGenerationGuard } from "../sync/syncGeneration";
import {
  connectionDraft,
  getSettings,
  isSyncConfigured,
  setSettings,
  subscribeSettings,
  type ConnectionDraft,
  type Settings,
} from "./settings";

export interface SyncStatus {
  isSyncing: boolean;
  message: string;
  error: string | null;
  lastSyncAt: number | null;
  retryAt: number | null;
  conflictCount: number;
  connection: RemoteConnectionStatus;
  storagePersistent: boolean | null;
}

interface SyncBroadcast {
  type: "complete" | "error";
  scope: string;
  at: number;
  error?: string;
}

const POLL_INTERVAL_MS = 30_000;
const MAX_RETRY_MS = 60_000;
const LEASE_MS = 45_000;

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object" && "message" in error) {
    return String((error as { message: unknown }).message);
  }
  return "Sync failed.";
}

function configKey(settings: Settings): string {
  return settings.syncMode === "proxy"
    ? `proxy|${settings.syncEndpoint}|${settings.connectionScope}|${settings.syncCapability}`
    : `direct|${settings.directSupabaseUrl}|${settings.directWorkspaceId}|${settings.connectionScope}|${settings.directSupabaseKey}`;
}

async function remoteFromDraft(draft: ConnectionDraft): Promise<SyncRemote> {
  if (draft.mode === "proxy") return new ProxyRemote(draft.endpoint, draft.capability);
  if (!import.meta.env.DEV) throw new Error("Direct Supabase mode is available only during local development.");
  const { DirectSupabaseRemote } = await import("../sync/directSupabaseRemote");
  return new DirectSupabaseRemote(draft.directUrl, draft.directKey, draft.directWorkspaceId);
}

async function remoteFromSettings(settings: Settings): Promise<SyncRemote> {
  return remoteFromDraft(connectionDraft(settings));
}

async function withDatabaseLease<T>(database: EarnlineDB, task: () => Promise<T>): Promise<{ ran: boolean; value?: T }> {
  const token = crypto.randomUUID();
  const now = Date.now();
  let acquired = false;
  try {
    await database.transaction("rw", database.syncLeases, async () => {
      const current = await database.syncLeases.get("sync");
      if (current && current.expiresAt > now) return;
      await database.syncLeases.put({ id: "sync", token, expiresAt: now + LEASE_MS });
      acquired = true;
    });
  } catch {
    // A closed/reconfigured database cannot safely start another sync pass.
    return { ran: false };
  }
  if (!acquired) return { ran: false };
  const heartbeat = setInterval(() => {
    void database.transaction("rw", database.syncLeases, async () => {
      const current = await database.syncLeases.get("sync");
      if (current?.token === token) {
        await database.syncLeases.put({ ...current, expiresAt: Date.now() + LEASE_MS });
      }
    }).catch(() => { /* A closed database leaves an expiring lease. */ });
  }, Math.floor(LEASE_MS / 3));
  try {
    return { ran: true, value: await task() };
  } finally {
    clearInterval(heartbeat);
    try {
      await database.transaction("rw", database.syncLeases, async () => {
        const current = await database.syncLeases.get("sync");
        if (current?.token === token) await database.syncLeases.delete("sync");
      });
    } catch {
      // Lease expires by itself.
    }
  }
}

async function withSyncLock<T>(
  scope: string,
  database: EarnlineDB,
  task: () => Promise<T>,
): Promise<{ ran: boolean; value?: T }> {
  if (navigator.locks?.request) {
    let output: { ran: boolean; value?: T } = { ran: false };
    await navigator.locks.request(`earnline-sync:${scope}`, { mode: "exclusive", ifAvailable: true }, async (lock) => {
      if (lock) output = { ran: true, value: await task() };
    });
    return output;
  }
  return withDatabaseLease(database, task);
}

class SyncController {
  private status: SyncStatus = {
    isSyncing: false,
    message: isSyncConfigured() ? "Ready" : "Offline",
    error: null,
    lastSyncAt: null,
    retryAt: null,
    conflictCount: 0,
    connection: "disconnected",
    storagePersistent: null,
  };
  private listeners = new Set<() => void>();
  private queueTimer: ReturnType<typeof setTimeout> | undefined;
  private retryTimer: ReturnType<typeof setTimeout> | undefined;
  private pollTimer: ReturnType<typeof setInterval> | undefined;
  private remoteUnsubscribe: (() => void) | undefined;
  private settingsUnsubscribe: (() => void) | undefined;
  private broadcast: BroadcastChannel | undefined;
  private started = false;
  private lastConfigKey = "";
  private attempts = new SyncGenerationGuard<EarnlineDB>();
  private followUpRequested = false;
  private retryAttempt = 0;
  private applyingConnection = false;

  getStatus = (): SyncStatus => this.status;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<SyncStatus>): void {
    this.status = { ...this.status, ...patch };
    for (const listener of this.listeners) listener();
  }

  async validateConnection(draft: ConnectionDraft): Promise<{ scope: string; transport: "proxy" | "direct" }> {
    this.set({ connection: "connecting", message: "Checking connection…", error: null });
    try {
      const remote = await remoteFromDraft(draft);
      const validation = await remote.validate();
      this.set({ connection: remote.transport === "proxy" ? "polling" : "connected", message: "Connection verified" });
      return validation;
    } catch (error) {
      this.set({ connection: "error", message: "Connection failed", error: errorMessage(error) });
      throw error;
    }
  }

  async validateAndApplyConnection(draft: ConnectionDraft): Promise<void> {
    const validation = await this.validateConnection(draft);
    const previousScope = getSettings().connectionScope;
    this.applyingConnection = true;
    try {
      const database = await activateDatabase(validation.scope, { migrateLegacy: previousScope === "" });
      if (database.scope !== validation.scope) throw new DOMException("Connection changed", "AbortError");
      const saved = setSettings({
        syncMode: draft.mode,
        syncEndpoint: draft.endpoint,
        syncCapability: draft.capability,
        directSupabaseUrl: draft.directUrl,
        directSupabaseKey: draft.directKey,
        directWorkspaceId: draft.directWorkspaceId,
        connectionScope: validation.scope,
        profileNeedsSync: false,
      });
      if (!saved) throw new Error("The connection was verified but could not be saved in this browser.");
    } finally {
      this.applyingConnection = false;
    }
    await this.reconfigure(true);
  }

  private async performSync(conflictResolution: ConflictResolution = "requireUserChoice"): Promise<void> {
    const settings = getSettings();
    if (!isSyncConfigured(settings)) {
      this.set({ message: "Offline", connection: "disconnected" });
      return;
    }
    if (!navigator.onLine) {
      this.set({ message: "Offline", connection: "disconnected" });
      this.scheduleRetry();
      return;
    }
    if (this.status.isSyncing) {
      this.followUpRequested = true;
      return;
    }

    const generation = this.attempts.generation;
    const scope = settings.connectionScope;
    const database = getDatabase();
    this.set({ isSyncing: true, message: "Syncing…", error: null, retryAt: null });
    const result = await withSyncLock(scope, database, async () => {
      const attempt = this.attempts.begin(database);
      const remote = await remoteFromSettings(settings);
      const metadata = await database.syncMetadata.get("sync");
      const profileSignature = `${settings.baseCurrencyCode}|${settings.secondaryCurrencyCode}|${settings.rate}`;
      const remoteProfile = await syncWorkspaceProfile(
        remote,
        {
          workspace_id: remote.rowWorkspace,
          base_currency_code: settings.baseCurrencyCode,
          secondary_currency_code: settings.secondaryCurrencyCode,
          exchange_rate: String(settings.rate),
        },
        settings.profileNeedsSync,
        attempt.signal,
      );
      if (!this.attempts.isCurrent(attempt, getDatabase())) throw new DOMException("Connection changed", "AbortError");
      const current = getSettings();
      const currentProfileSignature = `${current.baseCurrencyCode}|${current.secondaryCurrencyCode}|${current.rate}`;
      if (currentProfileSignature === profileSignature) {
        setSettings({
          baseCurrencyCode: remoteProfile.base_currency_code,
          secondaryCurrencyCode: remoteProfile.secondary_currency_code,
          rate: Number(remoteProfile.exchange_rate),
          profileNeedsSync: false,
        });
      } else {
        this.followUpRequested = true;
      }

      const nextCursor = await sync(remote, metadata?.rowCursorMs ?? null, {
        database,
        signal: attempt.signal,
        conflictResolution,
      });
      if (!this.attempts.isCurrent(attempt, getDatabase())) {
        throw new DOMException("Connection changed", "AbortError");
      }
      const completedAt = Date.now();
      await database.syncMetadata.put({ id: "sync", rowCursorMs: nextCursor, lastSyncAt: completedAt });
      this.attempts.finish(attempt);
      return completedAt;
    });

    if (!result.ran) {
      this.set({ isSyncing: false, message: "Syncing in another tab…" });
      this.queueSync(1200);
      return;
    }
    const completedAt = result.value;
    if (completedAt != null && generation === this.attempts.generation) {
      this.retryAttempt = 0;
      clearTimeout(this.retryTimer);
      this.set({
        isSyncing: false,
        message: "Synced",
        lastSyncAt: completedAt,
        retryAt: null,
        conflictCount: 0,
        connection: settings.syncMode === "proxy" ? "polling" : "connected",
      });
      this.broadcast?.postMessage({ type: "complete", scope, at: completedAt } satisfies SyncBroadcast);
    }
    if (this.followUpRequested && generation === this.attempts.generation) {
      this.followUpRequested = false;
      await this.performSync();
    }
  }

  private async runSync(conflictResolution: ConflictResolution = "requireUserChoice"): Promise<void> {
    try {
      await this.performSync(conflictResolution);
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        this.set({ isSyncing: false });
        return;
      }
      const conflictCount = error instanceof SyncConflictError ? error.count : 0;
      const message = errorMessage(error);
      this.set({
        isSyncing: false,
        message: conflictCount > 0 ? "Resolve conflict" : "Needs sync",
        error: message,
        conflictCount,
        connection: conflictCount > 0 ? this.status.connection : "error",
      });
      this.broadcast?.postMessage({ type: "error", scope: getSettings().connectionScope, at: Date.now(), error: message } satisfies SyncBroadcast);
      if (conflictCount === 0) this.scheduleRetry();
    }
  }

  async keepLocalConflictChanges(): Promise<void> {
    this.set({ conflictCount: 0, error: null });
    await this.runSync("preferLocal");
  }

  async useCloudConflictChanges(): Promise<void> {
    this.set({ conflictCount: 0, error: null });
    await this.runSync("preferRemote");
  }

  async syncNow(): Promise<void> {
    await this.runSync();
  }

  queueSync(delayMs = 1500): void {
    clearTimeout(this.queueTimer);
    this.queueTimer = setTimeout(() => void this.runSync(), delayMs);
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    window.addEventListener("focus", this.onWake);
    window.addEventListener("online", this.onWake);
    window.addEventListener("offline", this.onOffline);
    document.addEventListener("visibilitychange", this.onVisibility);
    this.settingsUnsubscribe = subscribeSettings(() => {
      if (!this.applyingConnection) void this.reconfigure();
      if (getSettings().profileNeedsSync && isSyncConfigured()) this.queueSync();
    });
    if (typeof BroadcastChannel !== "undefined") {
      this.broadcast = new BroadcastChannel("earnline-sync");
      this.broadcast.addEventListener("message", this.onBroadcast);
    }
    void requestPersistentStorage().then((persistent) => this.set({ storagePersistent: persistent }));
    void this.reconfigure(true);
  }

  stop(): void {
    if (!this.started) return;
    this.started = false;
    window.removeEventListener("focus", this.onWake);
    window.removeEventListener("online", this.onWake);
    window.removeEventListener("offline", this.onOffline);
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.settingsUnsubscribe?.();
    this.settingsUnsubscribe = undefined;
    this.attempts.invalidate();
    this.followUpRequested = false;
    this.teardownRemote();
    this.broadcast?.close();
    this.broadcast = undefined;
    clearTimeout(this.queueTimer);
    clearTimeout(this.retryTimer);
    this.set({ isSyncing: false, retryAt: null });
  }

  private onWake = (): void => {
    if (isSyncConfigured()) void this.runSync();
  };

  private onOffline = (): void => {
    this.set({ message: "Offline", connection: "disconnected" });
  };

  private onVisibility = (): void => {
    if (document.visibilityState === "visible") this.onWake();
  };

  private onBroadcast = (event: MessageEvent<SyncBroadcast>): void => {
    const message = event.data;
    if (!message || message.scope !== getSettings().connectionScope) return;
    if (message.type === "complete") {
      this.set({ message: "Synced", lastSyncAt: message.at, error: null, retryAt: null });
    }
  };

  private scheduleRetry(): void {
    if (!isSyncConfigured()) return;
    clearTimeout(this.retryTimer);
    const base = Math.min(MAX_RETRY_MS, 2000 * 2 ** this.retryAttempt);
    const delay = Math.round(base * (0.85 + Math.random() * 0.3));
    this.retryAttempt = Math.min(this.retryAttempt + 1, 6);
    const retryAt = Date.now() + delay;
    this.set({ retryAt });
    this.retryTimer = setTimeout(() => void this.runSync(), delay);
  }

  private async reconfigure(force = false): Promise<void> {
    const settings = getSettings();
    const key = configKey(settings);
    if (!force && key === this.lastConfigKey) return;
    this.lastConfigKey = key;
    this.attempts.invalidate();
    const generation = this.attempts.generation;
    this.teardownRemote();
    this.set({ isSyncing: false, conflictCount: 0, retryAt: null });
    if (!isSyncConfigured(settings)) {
      this.set({ message: "Offline", connection: "disconnected", lastSyncAt: null });
      return;
    }

    const database = await activateDatabase(settings.connectionScope);
    if (generation !== this.attempts.generation || database.scope !== settings.connectionScope) return;
    const metadata = await database.syncMetadata.get("sync");
    if (generation !== this.attempts.generation) return;
    const remote = await remoteFromSettings(settings);
    if (generation !== this.attempts.generation) return;
    if (remote.subscribe) {
      this.set({ connection: "connecting", message: "Connecting…", lastSyncAt: metadata?.lastSyncAt ?? null });
      this.remoteUnsubscribe = remote.subscribe(
        () => this.queueSync(600),
        (connection, error) => this.onRemoteStatus(connection, error),
      );
    } else {
      this.set({ connection: "polling", message: "Ready", lastSyncAt: metadata?.lastSyncAt ?? null });
      this.pollTimer = setInterval(() => {
        if (document.visibilityState === "visible") void this.runSync();
      }, POLL_INTERVAL_MS);
    }
    void this.runSync();
  }

  private onRemoteStatus(status: RemoteConnectionStatus, error?: string): void {
    this.set({
      connection: status,
      message: status === "connected" ? "Ready" : status === "connecting" ? "Connecting…" : this.status.message,
      error: error ?? this.status.error,
    });
    if (status === "error") this.scheduleRetry();
  }

  private teardownRemote(): void {
    this.remoteUnsubscribe?.();
    this.remoteUnsubscribe = undefined;
    clearInterval(this.pollTimer);
    this.pollTimer = undefined;
  }
}

export const syncController = new SyncController();

export function useSyncStatus(): SyncStatus {
  return useSyncExternalStore(syncController.subscribe, syncController.getStatus, syncController.getStatus);
}

export function queueSync(): void {
  syncController.queueSync();
}
