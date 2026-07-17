const projectURL = (process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL ?? "").trim();
const publishableKey = (process.env.SUPABASE_PUBLISHABLE_KEY ?? process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "").trim();
const ownerToken = (process.env.SUPABASE_OWNER_ACCESS_TOKEN ?? "").trim();
if (!projectURL || !publishableKey) throw new Error("Supabase URL and publishable key are required.");

const tables = [
  "earnline_clients", "earnline_entries", "earnline_headings",
  "earnline_tombstones", "earnline_profiles", "earnline_project_icons",
];
let failed = false;

async function fetchWithRetry(url, init = {}) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await fetch(url, { ...init, signal: AbortSignal.timeout(60_000) });
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
  const exposed = result.status >= 200 && result.status < 300 && Array.isArray(result.value) && result.value.length > 0;
  console.log(`anon ${table}: HTTP ${result.status}${exposed ? " EXPOSED" : " denied/empty"}`);
  if (exposed) failed = true;
}

const syncEndpoint = new URL("/functions/v1/earnline-sync", projectURL);
const syncResponse = await fetchWithRetry(syncEndpoint, {
  method: "POST",
  headers: { apikey: publishableKey, "content-type": "application/json" },
  body: JSON.stringify({ action: "validate" }),
});
console.log(`sync without user JWT: HTTP ${syncResponse.status}`);
if (syncResponse.ok) failed = true;

const pairEndpoint = new URL("/functions/v1/earnline-pair-device", projectURL);
const pairResponse = await fetchWithRetry(pairEndpoint, {
  method: "POST",
  headers: {
    apikey: publishableKey,
    authorization: `Bearer ${publishableKey}`,
    "content-type": "application/json",
  },
  body: JSON.stringify({ token: "00000000-0000-4000-8000-000000000000" }),
});
console.log(`pair with invalid token: HTTP ${pairResponse.status}`);
if (pairResponse.ok) failed = true;

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
