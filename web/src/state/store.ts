// Sync orchestration — the web analog of AppModel's sync methods.
// Drives syncNow / debounced queueSync, wires triggers (load, focus, online),
// and subscribes to Supabase Realtime so remote edits pull in live.

import { useSyncExternalStore } from "react";
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { getSupabase } from "../sync/supabaseClient";
import { sync } from "../sync/syncCoordinator";
import { getSettings, isSupabaseConfigured, setSettings, subscribeSettings } from "./settings";

export interface SyncStatus {
  isSyncing: boolean;
  message: string;
  error: string | null;
  lastSyncAt: number | null;
}

const REALTIME_TABLES = [
  "earnline_clients",
  "earnline_entries",
  "earnline_headings",
  "earnline_tombstones",
];

function errorMessage(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (typeof e === "string") return e;
  if (e && typeof e === "object" && "message" in e) return String((e as { message: unknown }).message);
  return "Sync failed.";
}

class SyncController {
  private status: SyncStatus;
  private listeners = new Set<() => void>();
  private queueTimer: ReturnType<typeof setTimeout> | undefined;
  private realtimeTimer: ReturnType<typeof setTimeout> | undefined;
  private channel: RealtimeChannel | undefined;
  private channelSupabase: SupabaseClient | undefined;
  private started = false;
  private lastConfigKey = "";

  constructor() {
    const s = getSettings();
    this.status = {
      isSyncing: false,
      message: isSupabaseConfigured(s) ? "Ready" : "Offline",
      error: null,
      lastSyncAt: s.lastSyncAt,
    };
  }

  getStatus = (): SyncStatus => this.status;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<SyncStatus>): void {
    this.status = { ...this.status, ...patch };
    for (const l of this.listeners) l();
  }

  async syncNow(): Promise<void> {
    const s = getSettings();
    if (!isSupabaseConfigured(s)) {
      this.set({ message: "Offline" });
      return;
    }
    if (this.status.isSyncing) return;
    this.set({ isSyncing: true, message: "Syncing…", error: null });
    try {
      const supabase = getSupabase(s.supabaseUrl, s.supabaseKey);
      const completedAt = await sync(supabase, s.workspaceId, s.lastSyncAt);
      setSettings({ lastSyncAt: completedAt });
      this.set({ isSyncing: false, message: "Synced", lastSyncAt: completedAt });
    } catch (e) {
      this.set({ isSyncing: false, message: "Needs sync", error: errorMessage(e) });
    }
  }

  queueSync(delayMs = 1500): void {
    clearTimeout(this.queueTimer);
    this.queueTimer = setTimeout(() => void this.syncNow(), delayMs);
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    window.addEventListener("focus", this.onWake);
    window.addEventListener("online", this.onWake);
    document.addEventListener("visibilitychange", this.onVisibility);
    subscribeSettings(() => this.reconfigure());
    this.reconfigure();
  }

  private onWake = (): void => {
    if (isSupabaseConfigured()) void this.syncNow();
  };

  private onVisibility = (): void => {
    if (document.visibilityState === "visible") this.onWake();
  };

  /** (Re)connect after the Supabase config changes; run an immediate sync. */
  private reconfigure(): void {
    const s = getSettings();
    const key = `${s.supabaseUrl}|${s.supabaseKey}|${s.workspaceId}`;
    if (key === this.lastConfigKey) return;
    this.lastConfigKey = key;

    this.teardownRealtime();
    if (!isSupabaseConfigured(s)) {
      this.set({ message: "Offline" });
      return;
    }
    this.set({ message: "Ready" });
    void this.syncNow();
    this.setupRealtime(getSupabase(s.supabaseUrl, s.supabaseKey), s.workspaceId);
  }

  private setupRealtime(supabase: SupabaseClient, workspaceId: string): void {
    let channel = supabase.channel(`earnline-sync:${workspaceId}`);
    for (const table of REALTIME_TABLES) {
      channel = channel.on(
        "postgres_changes",
        { event: "*", schema: "public", table, filter: `workspace_id=eq.${workspaceId}` },
        () => this.onRemoteChange(),
      );
    }
    channel.subscribe();
    this.channel = channel;
    this.channelSupabase = supabase;
  }

  private teardownRealtime(): void {
    if (this.channel && this.channelSupabase) {
      void this.channelSupabase.removeChannel(this.channel);
    }
    this.channel = undefined;
    this.channelSupabase = undefined;
  }

  /** Coalesce bursts of remote changes into a single follow-up sync. */
  private onRemoteChange(): void {
    clearTimeout(this.realtimeTimer);
    this.realtimeTimer = setTimeout(() => void this.syncNow(), 600);
  }
}

export const syncController = new SyncController();

export function useSyncStatus(): SyncStatus {
  return useSyncExternalStore(syncController.subscribe, syncController.getStatus, syncController.getStatus);
}

export function queueSync(): void {
  syncController.queueSync();
}
