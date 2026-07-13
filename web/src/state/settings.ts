// Persisted app settings with an explicit, validated sync connection. Editing a
// draft in Settings does not mutate the live transport or cursor.

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
export type SyncMode = "proxy" | "direct";

export interface ConnectionDraft {
  mode: SyncMode;
  endpoint: string;
  capability: string;
  directUrl: string;
  directKey: string;
  directWorkspaceId: string;
}

export interface Settings {
  baseCurrencyCode: string;
  secondaryCurrencyCode: string;
  rate: number;
  profileNeedsSync: boolean;
  syncMode: SyncMode;
  syncEndpoint: string;
  syncCapability: string;
  directSupabaseUrl: string;
  directSupabaseKey: string;
  directWorkspaceId: string;
  /** Opaque value returned only after the connection is validated. */
  connectionScope: string;
  theme: ThemePref;
}

const STORAGE_KEY = "earnline.settings";
const RATE_MIGRATION_KEY = "earnline.didApplyDefaultRate83";
let persistenceError: string | null = null;

function defaults(): Settings {
  return {
    baseCurrencyCode: DEFAULT_BASE_CURRENCY,
    secondaryCurrencyCode: DEFAULT_SECONDARY_CURRENCY,
    rate: DEFAULT_EXCHANGE_RATE,
    profileNeedsSync: false,
    syncMode: "proxy",
    syncEndpoint: (import.meta.env.VITE_EARNLINE_SYNC_ENDPOINT ?? "").toString().trim(),
    syncCapability: "",
    directSupabaseUrl: "",
    directSupabaseKey: "",
    directWorkspaceId: "",
    connectionScope: "",
    theme: "auto",
  };
}

function normalize(settings: Settings): Settings {
  const base = normalizedCurrencyCode(settings.baseCurrencyCode, DEFAULT_BASE_CURRENCY);
  let secondary = normalizedCurrencyCode(settings.secondaryCurrencyCode, DEFAULT_SECONDARY_CURRENCY);
  if (secondary === base) secondary = replacementCurrencyCode(base);
  return {
    baseCurrencyCode: base,
    secondaryCurrencyCode: secondary,
    rate: validExchangeRate(settings.rate),
    profileNeedsSync: settings.profileNeedsSync === true,
    syncMode: settings.syncMode === "direct" && import.meta.env.DEV ? "direct" : "proxy",
    syncEndpoint: settings.syncEndpoint.trim(),
    syncCapability: settings.syncCapability.trim(),
    // Never retain legacy direct database credentials in a production browser.
    directSupabaseUrl: import.meta.env.DEV ? settings.directSupabaseUrl.trim() : "",
    directSupabaseKey: import.meta.env.DEV ? settings.directSupabaseKey.trim() : "",
    directWorkspaceId: import.meta.env.DEV ? settings.directWorkspaceId.trim() : "",
    connectionScope: settings.connectionScope.trim(),
    theme: settings.theme === "light" || settings.theme === "dark" ? settings.theme : "auto",
  };
}

function migrate(raw: Partial<Settings> & Record<string, unknown>): Settings {
  const legacyUrl = typeof raw.supabaseUrl === "string" ? raw.supabaseUrl : "";
  const legacyKey = typeof raw.supabaseKey === "string" ? raw.supabaseKey : "";
  const legacyWorkspace = typeof raw.workspaceId === "string" ? raw.workspaceId : "";
  const merged: Settings = {
    ...defaults(),
    ...raw,
    // A legacy direct connection is deliberately not enabled in production.
    syncMode: raw.syncMode === "direct" && import.meta.env.DEV ? "direct" : "proxy",
    directSupabaseUrl: raw.directSupabaseUrl ?? legacyUrl,
    directSupabaseKey: raw.directSupabaseKey ?? legacyKey,
    directWorkspaceId: raw.directWorkspaceId ?? legacyWorkspace,
  } as Settings;
  return normalize(merged);
}

function load(): Settings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      localStorage.setItem(RATE_MIGRATION_KEY, "1");
      return normalize(defaults());
    }
    const parsed = migrate(JSON.parse(raw) as Partial<Settings> & Record<string, unknown>);
    if (localStorage.getItem(RATE_MIGRATION_KEY) === null) {
      parsed.rate = DEFAULT_EXCHANGE_RATE;
      localStorage.setItem(RATE_MIGRATION_KEY, "1");
    }
    const serialized = JSON.stringify(parsed);
    if (serialized !== raw) localStorage.setItem(STORAGE_KEY, serialized);
    return parsed;
  } catch {
    persistenceError = "Settings could not be loaded or migrated in this browser. Keep this tab open and export a backup.";
    return normalize(defaults());
  }
}

let current = load();
const listeners = new Set<() => void>();

function emit(): void {
  for (const listener of listeners) listener();
}

export function getSettings(): Settings {
  return current;
}

export function getSettingsPersistenceError(): string | null {
  return persistenceError;
}

export function clearSettingsPersistenceError(): void {
  persistenceError = null;
  emit();
}

export function setSettings(patch: Partial<Settings>): boolean {
  const previous = current;
  const next = normalize({ ...current, ...patch });
  const changesProfile =
    (patch.baseCurrencyCode !== undefined && next.baseCurrencyCode !== previous.baseCurrencyCode) ||
    (patch.secondaryCurrencyCode !== undefined && next.secondaryCurrencyCode !== previous.secondaryCurrencyCode) ||
    (patch.rate !== undefined && next.rate !== previous.rate);
  if (changesProfile && patch.profileNeedsSync === undefined) next.profileNeedsSync = true;
  const changesConnection =
    (patch.syncMode !== undefined && next.syncMode !== previous.syncMode) ||
    (patch.syncEndpoint !== undefined && next.syncEndpoint !== previous.syncEndpoint) ||
    (patch.syncCapability !== undefined && next.syncCapability !== previous.syncCapability) ||
    (patch.directSupabaseUrl !== undefined && next.directSupabaseUrl !== previous.directSupabaseUrl) ||
    (patch.directSupabaseKey !== undefined && next.directSupabaseKey !== previous.directSupabaseKey) ||
    (patch.directWorkspaceId !== undefined && next.directWorkspaceId !== previous.directWorkspaceId);
  if (changesConnection && patch.connectionScope === undefined) next.connectionScope = "";
  current = next;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
    persistenceError = null;
  } catch {
    persistenceError = "Settings could not be saved in this browser. Keep this tab open and export a backup.";
  }
  emit();
  return persistenceError == null;
}

export function connectionDraft(settings: Settings = current): ConnectionDraft {
  return {
    mode: settings.syncMode,
    endpoint: settings.syncEndpoint,
    capability: settings.syncCapability,
    directUrl: settings.directSupabaseUrl,
    directKey: settings.directSupabaseKey,
    directWorkspaceId: settings.directWorkspaceId,
  };
}

export function subscribeSettings(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useSettings(): Settings {
  return useSyncExternalStore(subscribeSettings, getSettings, getSettings);
}

export function useSettingsPersistenceError(): string | null {
  return useSyncExternalStore(subscribeSettings, getSettingsPersistenceError, getSettingsPersistenceError);
}

export function currencySettings(settings: Settings = current): CurrencySettings {
  return {
    baseCurrencyCode: settings.baseCurrencyCode,
    secondaryCurrencyCode: settings.secondaryCurrencyCode,
    rate: settings.rate,
  };
}

function validHttpsUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    const supportedProtocol = parsed.protocol === "https:" || (import.meta.env.DEV && parsed.protocol === "http:");
    return supportedProtocol && parsed.username === "" && parsed.password === "";
  } catch {
    return false;
  }
}

export function isSyncConfigured(settings: Settings = current): boolean {
  if (!/^[a-f0-9]{32}$/.test(settings.connectionScope)) return false;
  if (settings.syncMode === "proxy") {
    return validHttpsUrl(settings.syncEndpoint) && settings.syncCapability.length >= 24;
  }
  return import.meta.env.DEV && validHttpsUrl(settings.directSupabaseUrl) &&
    settings.directSupabaseKey !== "" && settings.directWorkspaceId !== "";
}

/** Backward-compatible name for existing call sites. */
export const isSupabaseConfigured = isSyncConfigured;

if (typeof window !== "undefined") {
  window.addEventListener("storage", (event) => {
    if (event.key !== STORAGE_KEY || event.newValue == null) return;
    try {
      current = migrate(JSON.parse(event.newValue) as Partial<Settings> & Record<string, unknown>);
      emit();
    } catch {
      // Ignore malformed writes from another tab; this tab keeps its valid copy.
    }
  });
}
