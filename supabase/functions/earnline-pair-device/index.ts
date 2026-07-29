import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@^2";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_REQUEST_BYTES = 2_048;

type PairingTokenRow = {
  token: string;
  expires_at: string;
  redeemed_at: string | null;
  redeemed_by: string | null;
  redeem_request_id: string | null;
};

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Server secret ${name} is not configured.`);
  return value;
}

function response(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
      "x-content-type-options": "nosniff",
    },
  });
}

function originAllowed(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return true;
  return env("EARNLINE_ALLOWED_ORIGINS")
    .split(",")
    .map((value) => new URL(value.trim()).origin)
    .includes(origin);
}

function withCors(request: Request, result: Response): Response {
  const headers = new Headers(result.headers);
  const origin = request.headers.get("origin");
  if (origin && originAllowed(request)) headers.set("access-control-allow-origin", origin);
  headers.set("access-control-allow-headers", "authorization, apikey, content-type");
  headers.set("access-control-allow-methods", "POST, OPTIONS");
  headers.append("vary", "Origin");
  return new Response(result.body, { status: result.status, statusText: result.statusText, headers });
}

function serviceClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function pairingToken(admin: SupabaseClient, token: string): Promise<PairingTokenRow | null> {
  const { data, error } = await admin
    .from("earnline_pairing_tokens")
    .select("token,expires_at,redeemed_at,redeemed_by,redeem_request_id")
    .eq("token", token)
    .limit(1);
  if (error) throw error;
  return (data?.[0] as PairingTokenRow | undefined) ?? null;
}

async function sessionForDeviceUser(
  admin: SupabaseClient,
  userID: string,
): Promise<{ access_token: string; refresh_token: string; expires_at: number | undefined }> {
  const { data: userData, error: userError } = await admin.auth.admin.getUserById(userID);
  const email = userData.user?.email;
  if (userError || !email) throw new Error("The paired device identity is unavailable.");

  const generatedLink = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const hashedToken = generatedLink.data?.properties?.hashed_token;
  if (generatedLink.error || !hashedToken) throw new Error("Could not authorize the device identity.");

  const publicClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const signedIn = await publicClient.auth.verifyOtp({ type: "magiclink", token_hash: hashedToken });
  if (signedIn.error || !signedIn.data.session) throw new Error("Could not start the device session.");
  return {
    access_token: signedIn.data.session.access_token,
    refresh_token: signedIn.data.session.refresh_token,
    expires_at: signedIn.data.session.expires_at,
  };
}

async function pairedUserForRequest(
  admin: SupabaseClient,
  token: string,
  requestID: string,
): Promise<string | null> {
  const record = await pairingToken(admin, token);
  return record?.redeemed_by && record.redeem_request_id === requestID ? record.redeemed_by : null;
}

export default {
  async fetch(request: Request): Promise<Response> {
    if (!originAllowed(request)) return withCors(request, response({ error: "Origin is not allowed." }, 403));
    if (request.method === "OPTIONS") return withCors(request, response({ ok: true }));
    if (request.method !== "POST") return withCors(request, response({ error: "Method not allowed." }, 405));
    const declaredLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > MAX_REQUEST_BYTES) {
      return withCors(request, response({ error: "Request body is too large." }, 413));
    }

    let createdUserID: string | undefined;
    let pairedUserID: string | undefined;
    let requestToken: string | undefined;
    let requestID: string | undefined;
    try {
      const rawBody = await request.text();
      if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BYTES) {
        return withCors(request, response({ error: "Request body is too large." }, 413));
      }
      const body = JSON.parse(rawBody) as { token?: unknown; request_id?: unknown };
      if (typeof body.token !== "string" || !UUID_PATTERN.test(body.token) ||
        typeof body.request_id !== "string" || !UUID_PATTERN.test(body.request_id)) {
        return withCors(request, response({ error: "Enter a valid pairing code." }, 400));
      }
      requestToken = body.token;
      requestID = body.request_id;

      const admin = serviceClient();
      const existing = await pairingToken(admin, body.token);
      if (!existing) return withCors(request, response({ error: "This pairing code is invalid or expired." }, 403));

      // Idempotent retry: the previous request claimed this token, but its
      // client never received the response. Issue a fresh session for that
      // exact device identity; never allocate another one.
      if (existing.redeemed_at !== null) {
        if (existing.redeemed_by && existing.redeem_request_id === body.request_id) {
          const tokens = await sessionForDeviceUser(admin, existing.redeemed_by);
          return withCors(request, response(tokens));
        }
        return withCors(request, response({ error: "This pairing code is invalid or expired." }, 403));
      }
      const random = crypto.randomUUID();
      const email = `device+${random}@devices.earnline.app`;
      const created = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        app_metadata: { earnline_device: true },
      });
      if (created.error || !created.data.user) throw new Error("Could not create a device identity.");
      createdUserID = created.data.user.id;

      const redeemed = await admin.rpc("earnline_redeem_pairing_token_for_user", {
        p_token: body.token,
        p_user_id: createdUserID,
        p_request_id: body.request_id,
      });
      if (redeemed.error) {
        // A concurrent identical retry can claim the token between our initial
        // read and the RPC. Recover its identity and remove this unused one.
        const recoveredUserID = await pairedUserForRequest(admin, body.token, body.request_id);
        if (!recoveredUserID) throw new Error("This pairing code is invalid or expired.");
        if (recoveredUserID === createdUserID) {
          // The RPC may have committed before its response was lost. This user
          // is already paired, so deleting it would burn the recovery path.
          pairedUserID = createdUserID;
        } else {
          await admin.auth.admin.deleteUser(createdUserID);
          createdUserID = undefined;
        }
        const tokens = await sessionForDeviceUser(admin, recoveredUserID);
        return withCors(request, response(tokens));
      }

      pairedUserID = createdUserID;
      const tokens = await sessionForDeviceUser(admin, pairedUserID);
      // Best-effort cleanup is cheap and bounds artifacts even if pg_cron is
      // unavailable in a future self-hosted deployment.
      void admin.rpc("earnline_cleanup_pairing_artifacts");
      return withCors(request, response(tokens));
    } catch (error) {
      // Only identities that never redeemed a token are safe to remove here.
      // Once paired, retaining it is what makes a lost response retryable.
      if (createdUserID && !pairedUserID && requestToken && requestID) {
        try {
          const recoveredUserID = await pairedUserForRequest(serviceClient(), requestToken, requestID);
          if (recoveredUserID === createdUserID) pairedUserID = createdUserID;
        } catch { /* Preserve the conservative cleanup decision below. */ }
      }
      if (createdUserID && createdUserID !== pairedUserID) {
        try {
          await serviceClient().auth.admin.deleteUser(createdUserID);
        } catch { /* Scheduled cleanup removes an orphan if this fails. */ }
      }
      console.error("earnline-pair-device failed", error instanceof Error ? error.message : "unknown error");
      return withCors(request, response({ error: "This device could not be paired." }, 400));
    }
  },
};
