// Whoop token exchange.
//
// This function exists for exactly one reason: Whoop's token endpoint is a
// confidential-client exchange, and WHOOP_CLIENT_SECRET must never be in the
// iOS binary. An .ipa is a zip file, so a secret compiled into the app is public
// the moment it ships.
//
// The secret is read from the function environment and is never logged, never
// returned, and never written to this repository. Set it with:
//
//   supabase secrets set WHOOP_CLIENT_SECRET=...
//
// The client sends { code, verifier, redirect_uri } and receives only the
// tokens. It never sees the secret.

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const clientID = Deno.env.get("WHOOP_CLIENT_ID");
  const clientSecret = Deno.env.get("WHOOP_CLIENT_SECRET");
  if (!clientID || !clientSecret) {
    // Deliberately does not say which one is missing.
    return json({ error: "server_not_configured" }, 500);
  }

  let body: { code?: string; verifier?: string; redirect_uri?: string;
              refresh_token?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const form = new URLSearchParams();
  form.set("client_id", clientID);
  form.set("client_secret", clientSecret);

  if (body.refresh_token) {
    form.set("grant_type", "refresh_token");
    form.set("refresh_token", body.refresh_token);
  } else {
    if (!body.code || !body.redirect_uri) {
      return json({ error: "missing_code" }, 400);
    }
    form.set("grant_type", "authorization_code");
    form.set("code", body.code);
    form.set("redirect_uri", body.redirect_uri);
    if (body.verifier) form.set("code_verifier", body.verifier);
  }

  const response = await fetch(WHOOP_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });

  const text = await response.text();
  if (!response.ok) {
    // Logged with the body so the cause is visible in function logs, while the
    // client receives only a status, because Whoop's errors can echo request parameters.
    console.error(`whoop token exchange failed: ${response.status} ${text.slice(0, 300)}`);
    return json({ error: "exchange_failed", status: response.status }, 502);
  }

  return new Response(text, {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
