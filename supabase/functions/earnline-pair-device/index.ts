import { createClient } from "npm:@supabase/supabase-js@^2";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

export default {
  async fetch(request: Request): Promise<Response> {
    if (!originAllowed(request)) return withCors(request, response({ error: "Origin is not allowed." }, 403));
    if (request.method === "OPTIONS") return withCors(request, response({ ok: true }));
    if (request.method !== "POST") return withCors(request, response({ error: "Method not allowed." }, 405));
    const declaredLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > 2_048) {
      return withCors(request, response({ error: "Request body is too large." }, 413));
    }

    let deviceUserID: string | undefined;
    try {
      const rawBody = await request.text();
      if (new TextEncoder().encode(rawBody).byteLength > 2_048) {
        return withCors(request, response({ error: "Request body is too large." }, 413));
      }
      const body = JSON.parse(rawBody) as { token?: unknown };
      if (typeof body.token !== "string" || !UUID_PATTERN.test(body.token)) {
        return withCors(request, response({ error: "Enter a valid pairing code." }, 400));
      }

      const url = env("SUPABASE_URL");
      const publishableKey = env("SUPABASE_ANON_KEY");
      const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
      const admin = createClient(url, serviceRoleKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });

      // Validate the token before allocating an Auth user. Invalid requests do
      // not create identities and therefore cannot be used for anonymous-user
      // amplification.
      const { data: tokenRows, error: tokenError } = await admin
        .from("earnline_pairing_tokens")
        .select("token")
        .eq("token", body.token)
        .is("redeemed_at", null)
        .gt("expires_at", new Date().toISOString())
        .limit(1);
      if (tokenError || tokenRows?.length !== 1) {
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
      deviceUserID = created.data.user.id;

      const redeemed = await admin.rpc("earnline_redeem_pairing_token_for_user", {
        p_token: body.token,
        p_user_id: deviceUserID,
      });
      if (redeemed.error) throw new Error("This pairing code is invalid or expired.");

      const publicClient = createClient(url, publishableKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      // Generate the short-lived session without enabling the public email /
      // password provider or sending a message to the synthetic address.
      const generatedLink = await admin.auth.admin.generateLink({ type: "magiclink", email });
      const hashedToken = generatedLink.data?.properties?.hashed_token;
      if (generatedLink.error || !hashedToken) throw new Error("Could not authorize the device identity.");
      const signedIn = await publicClient.auth.verifyOtp({ type: "magiclink", token_hash: hashedToken });
      if (signedIn.error || !signedIn.data.session) throw new Error("Could not start the device session.");

      // Best-effort cleanup is cheap and bounds artifacts even if pg_cron is
      // unavailable in a future self-hosted deployment.
      void admin.rpc("earnline_cleanup_pairing_artifacts");
      return withCors(request, response({
        access_token: signedIn.data.session.access_token,
        refresh_token: signedIn.data.session.refresh_token,
        expires_at: signedIn.data.session.expires_at,
      }));
    } catch (error) {
      if (deviceUserID) {
        try {
          const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
            auth: { autoRefreshToken: false, persistSession: false },
          });
          await admin.auth.admin.deleteUser(deviceUserID);
        } catch { /* A scheduled cleanup removes an orphan if this fails. */ }
      }
      console.error("earnline-pair-device failed", error instanceof Error ? error.message : "unknown error");
      return withCors(request, response({ error: "This device could not be paired." }, 400));
    }
  },
};
