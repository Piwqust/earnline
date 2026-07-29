const projectURL = (process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL ?? "").trim();
const publishableKey = (process.env.SUPABASE_PUBLISHABLE_KEY ?? process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "").trim();
const ownerToken = (process.env.SUPABASE_OWNER_ACCESS_TOKEN ?? "").trim();
if (!projectURL || !publishableKey) throw new Error("Supabase URL and publishable key are required.");

const tables = [
  "earnline_clients", "earnline_entries", "earnline_headings",
  "earnline_tombstones", "earnline_profiles", "earnline_project_icons",
  "earnline_month_reviews",
];
let failed = false;

async function fetchWithRetry(url, init = {}) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      // The verifier makes independent API and Function probes. Do not reuse a
      // stale keep-alive connection from an earlier endpoint and then mistake
      // a hanging response for an authorization result.
      return await fetch(url, {
        ...init,
        headers: { connection: "close", ...init.headers },
        signal: AbortSignal.timeout(60_000),
      });
    } catch (error) {
      lastError = error;
      if (attempt === 3) throw error;
      await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
    }
  }
  throw lastError;
}

async function rows(table, token) {
  const url = new URL(`/rest/v1/${table}`, projectURL);
  url.searchParams.set("select", "*");
  url.searchParams.set("limit", "1");
  const response = await fetchWithRetry(url, {
    headers: { apikey: publishableKey, authorization: `Bearer ${token}` },
  });
  const value = await response.json().catch(() => null);
  return { status: response.status, value };
}

for (const table of tables) {
  const result = await rows(table, publishableKey);
  const status = result.status;
  if (status === 401 || status === 403) {
    console.log(`anon ${table}: HTTP ${status} denied`);
  } else if (status >= 200 && status < 300) {
    const shape = Array.isArray(result.value) && result.value.length === 0 ? "empty result" : "rows returned";
    console.log(`anon ${table}: HTTP ${status} UNEXPECTED ${shape}`);
    failed = true;
  } else {
    console.log(`anon ${table}: HTTP ${status} UNEXPECTED infrastructure/schema response`);
    failed = true;
  }
}

const syncEndpoint = new URL("/functions/v1/earnline-sync", projectURL);
const syncResponse = await fetchWithRetry(syncEndpoint, {
  method: "POST",
  headers: { apikey: publishableKey, "content-type": "application/json" },
  body: JSON.stringify({ action: "validate" }),
});
console.log(`sync without user JWT: HTTP ${syncResponse.status}`);
if (syncResponse.status !== 401) failed = true;

const pairEndpoint = new URL("/functions/v1/earnline-pair-device", projectURL);
const pairResponse = await fetchWithRetry(pairEndpoint, {
  method: "POST",
  headers: {
    apikey: publishableKey,
    authorization: `Bearer ${publishableKey}`,
    "content-type": "application/json",
  },
  body: JSON.stringify({
    token: "00000000-0000-4000-8000-000000000000",
    request_id: "00000000-0000-4000-8000-000000000001",
  }),
});
console.log(`pair with invalid token: HTTP ${pairResponse.status}`);
if (pairResponse.status !== 403) failed = true;

// Trigger helpers must not be available through PostgREST RPC. They do not
// mutate data when called this way, but a 5xx would prove that the default
// EXECUTE grant accidentally exposed their implementation to anonymous users.
for (const functionName of [
  "earnline_entry_workspace_matches_client",
  "earnline_set_updated_at",
  "earnline_set_tombstone_clock",
  "earnline_stamp_tombstone",
]) {
  const response = await fetchWithRetry(new URL(`/rest/v1/rpc/${functionName}`, projectURL), {
    method: "POST",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${publishableKey}`,
      "content-type": "application/json",
    },
    body: "{}",
  });
  console.log(`anon ${functionName} RPC: HTTP ${response.status}`);
  // PostgREST removes functions without EXECUTE from its exposed schema cache,
  // so a denied helper is normally 404 rather than a table-style 401/403.
  if (![401, 403, 404].includes(response.status)) failed = true;
}

if (ownerToken) {
  for (const table of tables) {
    const result = await rows(table, ownerToken);
    console.log(`owner ${table}: HTTP ${result.status}`);
    if (result.status < 200 || result.status >= 300) failed = true;
  }
} else {
  console.log("owner checks: skipped (SUPABASE_OWNER_ACCESS_TOKEN is not set)");
}

if (failed) {
  console.error("Supabase security verification failed.");
  process.exitCode = 1;
} else {
  console.log("Supabase read-only security verification passed.");
}
