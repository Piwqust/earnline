import { useSyncExternalStore } from "react";
import type { Provider, Session, User } from "@supabase/supabase-js";
import { configuredSupabase } from "../sync/supabaseClient";

export type AuthState =
  | { status: "checking" }
  | { status: "signed-out"; message?: string }
  | { status: "redirecting" }
  | { status: "awaiting-workspace"; isPairedDevice: boolean }
  | { status: "ready"; session: Session; workspaceId: string; role: "owner" | "device"; isPairedDevice: boolean; email: string | null }
  | { status: "error"; message: string };

export interface PairingToken {
  token: string;
  expiresAt: string;
}

export interface PairedDevice {
  userId: string;
  createdAt: string;
  lastSignInAt: string | null;
}

interface WorkspaceRow {
  workspace_id: string;
  membership_role: "owner" | "device";
}

interface PairingTokenRow {
  pairing_token: string;
  expires_at: string;
}

interface PairedDeviceRow {
  user_id: string;
  created_at: string;
  last_sign_in_at: string | null;
}

interface DeviceSessionResponse {
  access_token?: string;
  refresh_token?: string;
  error?: string;
}

let current: AuthState = { status: "checking" };
const listeners = new Set<() => void>();
let started = false;
let unsubscribe: (() => void) | undefined;

function isDevelopmentOwnerPreview(): boolean {
  return import.meta.env.DEV && typeof window !== "undefined" &&
    new URLSearchParams(window.location.search).get("authPreview") === "owner";
}

function emit(next: AuthState): void {
  current = next;
  for (const listener of listeners) listener();
}

function configuredError(): string {
  return "This deployment is missing its public Supabase configuration.";
}

function message(error: unknown): string {
  return error instanceof Error && error.message.trim() ? error.message : "Could not complete account setup. Please try again.";
}

function isPairedIdentity(user: User): boolean {
  return user.is_anonymous === true || user.app_metadata?.earnline_device === true;
}

function pairDeviceEndpoint(): string {
  const configured = (import.meta.env.VITE_EARNLINE_PAIR_ENDPOINT ?? "").toString().trim();
  if (configured) return configured;
  const project = (import.meta.env.VITE_SUPABASE_URL ?? "").toString().trim();
  if (!project) throw new Error(configuredError());
  return new URL("/functions/v1/earnline-pair-device", project).toString();
}

async function resolveWorkspace(session: Session): Promise<void> {
  const client = configuredSupabase();
  if (!client) {
    emit({ status: "error", message: configuredError() });
    return;
  }
  const { data, error } = await client.rpc("earnline_current_workspace");
  if (error) {
    emit({ status: "error", message: message(error) });
    return;
  }
  const row = (Array.isArray(data) ? data[0] : data) as WorkspaceRow | null;
  if (!row?.workspace_id || (row.membership_role !== "owner" && row.membership_role !== "device")) {
    emit({ status: "awaiting-workspace", isPairedDevice: isPairedIdentity(session.user) });
    return;
  }
  emit({
    status: "ready",
    session,
    workspaceId: row.workspace_id,
    role: row.membership_role,
    isPairedDevice: isPairedIdentity(session.user),
    email: isPairedIdentity(session.user) ? null : session.user.email ?? null,
  });
}

export const authStore = {
  start(): void {
    if (started) return;
    started = true;
    if (isDevelopmentOwnerPreview()) {
      emit({
        status: "ready",
        session: {} as Session,
        workspaceId: "ui-preview-workspace",
        role: "owner",
        isPairedDevice: false,
        email: "owner@example.com",
      });
      return;
    }
    const client = configuredSupabase();
    if (!client) {
      emit({ status: "error", message: configuredError() });
      return;
    }
    unsubscribe = client.auth.onAuthStateChange((_event, session) => {
      if (!session) emit({ status: "signed-out" });
      else void resolveWorkspace(session);
    }).data.subscription.unsubscribe;
    void this.refresh();
  },

  stop(): void {
    unsubscribe?.();
    unsubscribe = undefined;
    started = false;
  },

  async refresh(): Promise<void> {
    const client = configuredSupabase();
    if (!client) {
      emit({ status: "error", message: configuredError() });
      return;
    }
    emit({ status: "checking" });
    const { data: { session }, error } = await client.auth.getSession();
    if (error) {
      emit({ status: "error", message: message(error) });
    } else if (!session) {
      emit({ status: "signed-out" });
    } else {
      await resolveWorkspace(session);
    }
  },

  async beginOAuth(provider: Provider): Promise<void> {
    const client = configuredSupabase();
    if (!client) {
      emit({ status: "error", message: configuredError() });
      return;
    }
    emit({ status: "redirecting" });
    const { error } = await client.auth.signInWithOAuth({
      provider,
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });
    if (error) emit({ status: "error", message: message(error) });
  },

  async completeCallback(): Promise<void> {
    const client = configuredSupabase();
    if (!client) {
      emit({ status: "error", message: configuredError() });
      return;
    }

    // With PKCE and `detectSessionInUrl`, supabase-js consumes the code while
    // the client initializes. Prefer that session so this screen never races
    // a second exchange against the same one-time code.
    const { data: current, error: currentError } = await client.auth.getSession();
    if (currentError) {
      emit({ status: "error", message: message(currentError) });
      return;
    }
    if (current.session) {
      await resolveWorkspace(current.session);
      return;
    }

    const { data, error } = await client.auth.exchangeCodeForSession(window.location.href);
    if (error || !data.session) {
      emit({ status: "error", message: message(error ?? new Error("The sign-in callback did not include a session.")) });
      return;
    }
    await resolveWorkspace(data.session);
  },

  async redeemPairingCode(raw: string): Promise<void> {
    const token = pairingToken(raw);
    if (!token) {
      emit({ status: "error", message: "Enter a valid pairing code." });
      return;
    }
    const client = configuredSupabase();
    if (!client) {
      emit({ status: "error", message: configuredError() });
      return;
    }
    emit({ status: "checking" });
    const key = (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "").toString().trim();
    const response = await fetch(pairDeviceEndpoint(), {
      method: "POST",
      headers: { "content-type": "application/json", apikey: key, authorization: `Bearer ${key}` },
      body: JSON.stringify({ token }),
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
    });
    const payload = await response.json().catch(() => ({})) as DeviceSessionResponse;
    if (!response.ok || !payload.access_token || !payload.refresh_token) {
      emit({ status: "error", message: payload.error || "This device could not be paired." });
      return;
    }
    const { data, error } = await client.auth.setSession({
      access_token: payload.access_token,
      refresh_token: payload.refresh_token,
    });
    if (error || !data.session) {
      emit({ status: "error", message: message(error ?? new Error("Could not start the paired-device session.")) });
      return;
    }
    await resolveWorkspace(data.session);
  },

  async createPairingToken(): Promise<PairingToken> {
    const client = configuredSupabase();
    if (!client || current.status !== "ready" || current.role !== "owner" || current.isPairedDevice) {
      throw new Error("Only the workspace owner can pair a device.");
    }
    const { data, error } = await client.rpc("earnline_create_pairing_token");
    const row = (Array.isArray(data) ? data[0] : data) as PairingTokenRow | null;
    if (error || !row?.pairing_token || !row.expires_at) throw error ?? new Error("The pairing service returned an invalid response.");
    return { token: row.pairing_token, expiresAt: row.expires_at };
  },

  async listDevices(): Promise<PairedDevice[]> {
    if (isDevelopmentOwnerPreview()) {
      return [{
        userId: "bd078f2d-d828-4d64-b631-69e2c28d046e",
        createdAt: new Date(Date.now() - 14 * 86_400_000).toISOString(),
        lastSignInAt: new Date(Date.now() - 2 * 3_600_000).toISOString(),
      }];
    }
    const client = configuredSupabase();
    if (!client || current.status !== "ready" || current.role !== "owner" || current.isPairedDevice) {
      throw new Error("Only the workspace owner can manage devices.");
    }
    const { data, error } = await client.rpc("earnline_list_devices");
    if (error) throw error;
    return ((data ?? []) as PairedDeviceRow[]).map((row) => ({
      userId: row.user_id,
      createdAt: row.created_at,
      lastSignInAt: row.last_sign_in_at,
    }));
  },

  async revokeDevice(userId: string): Promise<void> {
    if (isDevelopmentOwnerPreview()) return;
    const client = configuredSupabase();
    if (!client || current.status !== "ready" || current.role !== "owner" || current.isPairedDevice) {
      throw new Error("Only the workspace owner can manage devices.");
    }
    const { data, error } = await client.rpc("earnline_revoke_device", { p_user_id: userId });
    if (error) throw error;
    if (data !== true) throw new Error("This paired device is no longer connected.");
  },

  async signOut(): Promise<void> {
    const client = configuredSupabase();
    if (!client) {
      emit({ status: "signed-out" });
      return;
    }
    try {
      const pairedDevice = (current.status === "ready" && current.isPairedDevice) ||
        (current.status === "awaiting-workspace" && current.isPairedDevice);
      if (pairedDevice) {
        const { data, error } = await client.rpc("earnline_disconnect_current_device");
        if (error) throw error;
        if (data !== true) throw new Error("This paired device is no longer connected.");
      }
      const { error } = await client.auth.signOut({ scope: "local" });
      if (error) throw error;
      emit({ status: "signed-out" });
    } catch (error) {
      emit({ status: "error", message: `Could not sign out safely. ${message(error)}` });
    }
  },
};

function pairingToken(raw: string): string | null {
  const text = raw.trim();
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)) return text;
  try {
    const url = new URL(text);
    if (url.protocol === "earnline-pairing:" && url.hostname === "v1") return pairingToken(url.pathname.slice(1));
  } catch { /* Manual fallback handles invalid text. */ }
  return null;
}

export function useAuthState(): AuthState {
  return useSyncExternalStore((listener) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  }, () => current, () => current);
}

export function accountLabel(user: User, isPairedDevice: boolean): string {
  return isPairedDevice ? "Paired device" : user.email ?? "Signed-in account";
}
