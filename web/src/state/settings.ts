// App settings — the web analog of AppModel's UserDefaults-backed state.
// Persisted in localStorage, exposed as a tiny reactive store (useSyncExternalStore).

import { useSyncExternalStore } from "react";
import {
  DEFAULT_BASE_CURRENCY,
  DEFAULT_SECONDARY_CURRENCY,
  DEFAULT_EXCHANGE_RATE,
  normalizedCurrencyCode,
  replacementCurrencyCode,
  validExchangeRate,
  type CurrencySettings,
} from "../domain/currency";

export type ThemePref = "auto" | "light" | "dark";

export interface Settings {
  baseCurrencyCode: string;
  secondaryCurrencyCode: string;
  rate: number;
  /** Currency tuple has changed locally and must win on the next profile sync. */
  profileNeedsSync: boolean;
  supabaseUrl: string;
  supabaseKey: string;
  workspaceId: string;
  /** When the last sync completed — display only ("Last sync" in Settings). */
  lastSyncAt: number | null;
  /** Incremental pull cursor: the newest server `updated_at`/`deleted_at` seen.
   *  Kept distinct from `lastSyncAt` so a client clock can't skew the cursor. */
  syncCursorMs: number | null;
  theme: ThemePref;
}

const STORAGE_KEY = "earnline.settings";
const RATE_MIGRATION_KEY = "earnline.didApplyDefaultRate83";

function envDefault(key: keyof ImportMetaEnv): string {
  return (import.meta.env[key] ?? "").toString().trim();
}

function defaults(): Settings {
  return {
    baseCurrencyCode: DEFAULT_BASE_CURRENCY,
    secondaryCurrencyCode: DEFAULT_SECONDARY_CURRENCY,
    rate: DEFAULT_EXCHANGE_RATE,
    profileNeedsSync: false,
    supabaseUrl: envDefault("VITE_SUPABASE_URL"),
    supabaseKey: envDefault("VITE_SUPABASE_ANON_KEY"),
    workspaceId: envDefault("VITE_WORKSPACE_ID"),
    lastSyncAt: null,
    syncCursorMs: null,
    theme: "auto",
  };
}

/** Apply the same normalization rules AppModel enforces in its didSet observers. */
function normalize(s: Settings): Settings {
  const base = normalizedCurrencyCode(s.baseCurrencyCode, DEFAULT_BASE_CURRENCY);
  let secondary = normalizedCurrencyCode(s.secondaryCurrencyCode, DEFAULT_SECONDARY_CURRENCY);
  if (secondary === base) secondary = replacementCurrencyCode(base);
  return {
    baseCurrencyCode: base,
    secondaryCurrencyCode: secondary,
    rate: validExchangeRate(s.rate),
    profileNeedsSync: s.profileNeedsSync === true,
    supabaseUrl: s.supabaseUrl.trim(),
    supabaseKey: s.supabaseKey.trim(),
    workspaceId: s.workspaceId.trim(),
    lastSyncAt: s.lastSyncAt ?? null,
    syncCursorMs: s.syncCursorMs ?? null,
    theme: s.theme === "light" || s.theme === "dark" ? s.theme : "auto",
  };
}

function load(): Settings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      localStorage.setItem(RATE_MIGRATION_KEY, "1");
      return normalize(defaults());
    }
    const rawObj = JSON.parse(raw) as Partial<Settings>;
    const parsed = normalize({ ...defaults(), ...rawObj });
    // Migrate installs from before the cursor/display split: their `lastSyncAt`
    // doubled as the pull cursor, so seed `syncCursorMs` from it once.
    if (!("syncCursorMs" in rawObj)) {
      parsed.syncCursorMs = parsed.lastSyncAt;
    }
    // One-time reset to the current shipped rate (mirrors AppModel.init):
    // values carried over from older builds move to the new default on first
    // load; afterwards whatever the user types always wins.
    if (localStorage.getItem(RATE_MIGRATION_KEY) === null) {
      parsed.rate = DEFAULT_EXCHANGE_RATE;
      localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed));
      localStorage.setItem(RATE_MIGRATION_KEY, "1");
    }
    return parsed;
  } catch {
    return normalize(defaults());
  }
}

let current = load();
const listeners = new Set<() => void>();

function emit() {
  for (const l of listeners) l();
}

export function getSettings(): Settings {
  return current;
}

export function setSettings(patch: Partial<Settings>): void {
  const prev = current;
  const next = normalize({ ...current, ...patch });
  // A different workspace invalidates the incremental pull cursor (mirrors
  // AppModel.workspaceID.didSet on iOS): otherwise a non-empty local DB keeps
  // the old workspace's cursor and never pulls the new workspace's older rows.
  if (next.workspaceId !== prev.workspaceId) {
    next.lastSyncAt = null;
    next.syncCursorMs = null;
  }
  const changesCurrencyProfile =
    (patch.baseCurrencyCode !== undefined && next.baseCurrencyCode !== prev.baseCurrencyCode) ||
    (patch.secondaryCurrencyCode !== undefined && next.secondaryCurrencyCode !== prev.secondaryCurrencyCode) ||
    (patch.rate !== undefined && next.rate !== prev.rate);
  if (changesCurrencyProfile && patch.profileNeedsSync === undefined) {
    next.profileNeedsSync = true;
  }
  current = next;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // best-effort persistence
  }
  emit();
}

export function subscribeSettings(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useSettings(): Settings {
  return useSyncExternalStore(subscribeSettings, getSettings, getSettings);
}

export function currencySettings(s: Settings = current): CurrencySettings {
  return {
    baseCurrencyCode: s.baseCurrencyCode,
    secondaryCurrencyCode: s.secondaryCurrencyCode,
    rate: s.rate,
  };
}

export function isSupabaseConfigured(s: Settings = current): boolean {
  if (s.supabaseKey.trim() === "" || s.workspaceId.trim() === "") return false;
  try {
    new URL(s.supabaseUrl.trim());
    return true;
  } catch {
    return false;
  }
}
