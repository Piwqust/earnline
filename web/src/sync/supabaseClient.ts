// Thin cached factory for the Supabase client. No-login model: we connect with
// the project's publishable (anon) key, so session persistence is disabled.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let cached: { url: string; key: string; client: SupabaseClient } | null = null;

export function getSupabase(url: string, key: string): SupabaseClient {
  if (cached && cached.url === url && cached.key === key) return cached.client;
  const client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  cached = { url, key, client };
  return client;
}
