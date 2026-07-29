import { randomUUID } from "node:crypto";

const projectRef = (process.env.SUPABASE_PROJECT_REF ?? "").trim();
const projectURL = (process.env.SUPABASE_URL ?? "").trim();
const publishableKey = (process.env.SUPABASE_PUBLISHABLE_KEY ?? "").trim();
const serviceRoleKey = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? "").trim();
const managementToken = (process.env.SUPABASE_ACCESS_TOKEN ?? "").trim();
if (![projectRef, projectURL, publishableKey, serviceRoleKey, managementToken].every(Boolean)) {
  throw new Error("Project ref, URL, public key, service role key, and Management API token are required.");
}

const workspaceID = `e2e-${randomUUID()}`;
const password = `${randomUUID().replaceAll("-", "")}${randomUUID().replaceAll("-", "")}Aa1!`;
const email = `earnline-e2e+${randomUUID()}@example.com`;
let ownerUserID;
let deviceUserID;
let ownerToken;

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function jsonRequest(url, init, expected = (status) => status >= 200 && status < 300, attempts = 1) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const response = await fetch(url, { ...init, signal: AbortSignal.timeout(120_000) });
      const text = await response.text();
      const value = text ? JSON.parse(text) : null;
      if (!expected(response.status)) {
        throw new Error(`${new URL(url).pathname} returned HTTP ${response.status}: ${value?.message ?? value?.error ?? "request failed"}`);
      }
      return { status: response.status, value };
    } catch (error) {
      lastError = error;
      if (attempt === attempts) throw error;
      await new Promise((resolve) => setTimeout(resolve, 1_000 * attempt));
    }
  }
  throw lastError;
}

async function managementQuery(query) {
  return jsonRequest(`https://api.supabase.com/v1/projects/${projectRef}/database/query`, {
    method: "POST",
    headers: { authorization: `Bearer ${managementToken}`, "content-type": "application/json" },
    body: JSON.stringify({ query }),
  });
}

async function admin(path, method, body) {
  return jsonRequest(new URL(`/auth/v1/admin/${path}`, projectURL), {
    method,
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      "content-type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  }, undefined, method === "DELETE" ? 3 : 1);
}

async function rpc(name, token, body = {}, attempts = 3) {
  return jsonRequest(new URL(`/rest/v1/rpc/${name}`, projectURL), {
    method: "POST",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  }, undefined, attempts);
}

async function edge(name, token, body, attempts = 1) {
  return jsonRequest(new URL(`/functions/v1/${name}`, projectURL), {
    method: "POST",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  }, undefined, attempts);
}

function jwtSubject(token) {
  const payload = token.split(".")[1];
  if (!payload) throw new Error("Device session did not contain a JWT.");
  return JSON.parse(Buffer.from(payload, "base64url").toString("utf8")).sub;
}

try {
  const created = await admin("users", "POST", {
    email,
    password,
    email_confirm: true,
    user_metadata: { purpose: "earnline-e2e-verification" },
  });
  ownerUserID = created.value?.id;
  if (!ownerUserID) throw new Error("Could not create the temporary owner.");

  await managementQuery(`
    insert into public.earnline_workspaces (id, owner_id)
    values (${sqlLiteral(workspaceID)}, ${sqlLiteral(ownerUserID)}::uuid);
    insert into public.earnline_workspace_members (workspace_id, user_id, role)
    values (${sqlLiteral(workspaceID)}, ${sqlLiteral(ownerUserID)}::uuid, 'owner');
  `);

  let signedIn;
  try {
    signedIn = await jsonRequest(new URL("/auth/v1/token?grant_type=password", projectURL), {
      method: "POST",
      headers: { apikey: publishableKey, "content-type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
  } catch {
    // Production intentionally disables the email/password provider. An
    // admin-generated magic link does not send mail and still yields a genuine
    // short-lived user session for this isolated verification identity.
    const link = await admin("generate_link", "POST", { type: "magiclink", email });
    const hashedToken = link.value?.hashed_token;
    if (!hashedToken) throw new Error("Could not generate the temporary owner session.");
    signedIn = await jsonRequest(new URL("/auth/v1/verify", projectURL), {
      method: "POST",
      headers: { apikey: publishableKey, "content-type": "application/json" },
      body: JSON.stringify({ type: "magiclink", token_hash: hashedToken }),
    });
  }
  ownerToken = signedIn.value?.access_token;
  if (!ownerToken) throw new Error("Could not start the temporary owner session.");

  const membership = await rpc("earnline_current_workspace", ownerToken);
  if (membership.value?.[0]?.membership_role !== "owner") throw new Error("Owner membership was not resolved.");
  await edge("earnline-sync", ownerToken, { action: "validate" }, 3);
  console.log("owner membership and sync: passed");

  console.log("creating one-use pairing token…");
  const pairing = await rpc("earnline_create_pairing_token", ownerToken);
  const pairingToken = pairing.value?.[0]?.pairing_token;
  if (!pairingToken) throw new Error("Could not create a pairing token.");
  console.log("redeeming pairing token…");
  const pairingRequestID = randomUUID();
  const pairingRequest = { token: pairingToken, request_id: pairingRequestID };
  const paired = await edge("earnline-pair-device", publishableKey, pairingRequest, 3);
  const deviceToken = paired.value?.access_token;
  if (!deviceToken) throw new Error("Pairing did not return a device session.");
  const retry = await edge("earnline-pair-device", publishableKey, pairingRequest, 3);
  if (!retry.value?.access_token || jwtSubject(retry.value.access_token) !== jwtSubject(deviceToken)) {
    throw new Error("A pairing retry created a different device identity.");
  }
  console.log("idempotent pairing retry: passed");
  deviceUserID ??= jwtSubject(deviceToken);
  console.log("validating paired-device sync…");
  await edge("earnline-sync", deviceToken, { action: "validate" }, 3);
  console.log("one-use device pairing and sync: passed");

  console.log("listing and revoking paired device…");
  const devices = await rpc("earnline_list_devices", ownerToken);
  if (!devices.value?.some((device) => device.user_id === deviceUserID)) throw new Error("Paired device was not listed.");
  const revoked = await rpc("earnline_revoke_device", ownerToken, { p_user_id: deviceUserID });
  if (revoked.value !== true) {
    // A lost successful response followed by a retry returns false because the
    // identity has already been deleted. The postcondition, not the first
    // response packet, is authoritative.
    const remainingDevices = await rpc("earnline_list_devices", ownerToken);
    if (remainingDevices.value?.some((device) => device.user_id === deviceUserID)) {
      throw new Error("Owner could not revoke the paired device.");
    }
  }
  deviceUserID = undefined;

  const rejected = await fetch(new URL("/functions/v1/earnline-sync", projectURL), {
    method: "POST",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${deviceToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ action: "validate" }),
    signal: AbortSignal.timeout(120_000),
  });
  if (rejected.ok) throw new Error("Revoked device retained sync access.");
  console.log(`device revocation: passed (HTTP ${rejected.status})`);
  console.log("Supabase owner/device E2E verification passed.");
} finally {
  if (deviceUserID) {
    await admin(`users/${deviceUserID}`, "DELETE").catch(() => undefined);
  }
  if (ownerUserID) {
    await managementQuery(`delete from public.earnline_workspaces where id = ${sqlLiteral(workspaceID)}`)
      .catch(() => undefined);
    await admin(`users/${ownerUserID}`, "DELETE").catch(() => undefined);
  }
}
