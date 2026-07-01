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

export interface Settings {
  baseCurrencyCode: string;
  secondaryCurrencyCode: string;
  rate: number;
  supabaseUrl: string;
  supabaseKey: string;
  workspaceId: string;
  lastSyncAt: number | null;
}

const STORAGE_KEY = "earnline.settings";

function envDefault(key: keyof ImportMetaEnv): string {
  return (import.meta.env[key] ?? "").toString().trim();
}

function defaults(): Settings {
  return {
    baseCurrencyCode: DEFAULT_BASE_CURRENCY,
    secondaryCurrencyCode: DEFAULT_SECONDARY_CURRENCY,
    rate: DEFAULT_EXCHANGE_RATE,
    supabaseUrl: envDefault("VITE_SUPABASE_URL"),
    supabaseKey: envDefault("VITE_SUPABASE_ANON_KEY"),
    workspaceId: envDefault("VITE_WORKSPACE_ID"),
    lastSyncAt: null,
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
    supabaseUrl: s.supabaseUrl.trim(),
    supabaseKey: s.supabaseKey.trim(),
    workspaceId: s.workspaceId.trim(),
    lastSyncAt: s.lastSyncAt ?? null,
  };
}

function load(): Settings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return normalize(defaults());
    return normalize({ ...defaults(), ...JSON.parse(raw) });
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
  const next = normalize({ ...current, ...patch });
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
