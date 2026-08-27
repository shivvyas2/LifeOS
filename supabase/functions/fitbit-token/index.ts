// Fitbit authorization code exchange.
//
// FITBIT_CLIENT_SECRET must never be in the iOS binary: an .ipa is a zip file,
// so a secret compiled into the app is public the moment it ships. Set it with
//
//   supabase secrets set FITBIT_CLIENT_SECRET=...
//
// The client sends { code, verifier, redirect_uri } and receives only a
// confirmation. Unlike the Whoop arrangement, it does not receive the tokens
// either: Fitbit refresh tokens rotate and are single use, so exactly one
// writer may hold them, and that writer is this database row.

import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";
import { classifyFitbitFailure, FITBIT_TOKEN_URL, tokenForm } from "../_shared/fitbit.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // A security boundary, not a formality: this writes a health credential
  // keyed by user, so the id must come from the caller's own token and never
  // from the request body.
  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  const clientID = Deno.env.get("FITBIT_CLIENT_ID");
  const clientSecret = Deno.env.get("FITBIT_CLIENT_SECRET");
  // Deliberately does not say which one is missing.
  if (!clientID || !clientSecret) return json({ error: "server_not_configured" }, 500);

  let body: { code?: string; verifier?: string; redirect_uri?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!body.code || !body.redirect_uri) return json({ error: "missing_code" }, 400);

  const response = await fetch(FITBIT_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${btoa(`${clientID}:${clientSecret}`)}`,
    },
    body: tokenForm(body),
  });

  const text = await response.text();
  if (!response.ok) {
    // Logged with the body so the cause is visible in function logs, while the
    // client receives only a kind, because Fitbit's errors echo request
    // parameters.
    console.error(`fitbit token exchange failed: ${response.status} ${text.slice(0, 300)}`);
    return json({ error: classifyFitbitFailure(response.status, text) }, 502);
  }

  const tokens = JSON.parse(text) as {
    access_token: string;
    refresh_token: string;
    expires_in: number;
    scope: string;
    user_id: string;
  };

  const expiresAt = new Date(Date.now() + (tokens.expires_in ?? 28_800) * 1000);

  // Upsert, not insert: reconnecting replaces a dead credential in place, and
  // a second row per user is meaningless when the primary key is the user.
  const { error } = await serviceClient()
    .from("fitbit_connections")
    .upsert({
      user_id: userID,
      fitbit_user_id: tokens.user_id,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      access_expires_at: expiresAt.toISOString(),
      scopes: tokens.scope ?? "",
      needs_reauth: false,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });

  if (error) {
    console.error(`fitbit connection write failed: ${error.message}`);
    return json({ error: "storage_failure" }, 500);
  }

  // No token in the response. This is the whole point of the arrangement.
  return json({ connected: true, fitbit_user_id: tokens.user_id, scopes: tokens.scope ?? "" }, 200);
});
