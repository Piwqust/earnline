// Thin cached factory for browser-authenticated Supabase clients. Publishable
// keys are intentionally public; sessions are persisted by supabase-js and
// every data request is constrained by membership-based RLS.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let cached: { url: string; key: string; client: SupabaseClient } | null = null;

export function getSupabase(url: string, key: string): SupabaseClient {
  if (cached && cached.url === url && cached.key === key) return cached.client;
  const client = createClient(url, key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      // Let supabase-js consume the PKCE callback during client initialization.
      // The callback screen then reads the persisted session instead of racing
      // a second manual exchange against that initialization.
      detectSessionInUrl: true,
      flowType: "pkce",
    },
  });
  cached = { url, key, client };
  return client;
}

export function configuredSupabase(): SupabaseClient | null {
  const url = (import.meta.env.VITE_SUPABASE_URL ?? "").toString().trim();
  const key = (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "").toString().trim();
  if (!url || !key) return null;
  return getSupabase(url, key);
}
