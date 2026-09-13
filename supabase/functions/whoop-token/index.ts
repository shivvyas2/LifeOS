import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
type Connection = {
  access_token: string;
  refresh_token: string | null;
  access_expires_at: string;
};

function tokens(row: Connection): Response {
  return json({ access_token: row.access_token, refresh_token: row.refresh_token,
    expires_in: Math.max(0, (Date.parse(row.access_expires_at) - Date.now()) / 1000) }, 200);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST" && req.method !== "DELETE") return json({ error: "method_not_allowed" }, 405);
  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);
  const db = serviceClient();
  if (req.method === "DELETE") {
    const { error } = await db.from("whoop_connections").delete().eq("user_id", userID);
    return error ? json({ error: "disconnect_failed" }, 500) : json({ disconnected: true }, 200);
  }
  const clientID = Deno.env.get("WHOOP_CLIENT_ID");
  const clientSecret = Deno.env.get("WHOOP_CLIENT_SECRET");
  if (!clientID || !clientSecret) return json({ error: "server_not_configured" }, 500);

  let body: { code?: string; verifier?: string; redirect_uri?: string; refresh_token?: string; action?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }
  const { data: existing, error: readError } = await db.from("whoop_connections")
    .select("access_token,refresh_token,access_expires_at").eq("user_id", userID).maybeSingle<Connection>();
  if (readError) return json({ error: "storage_unavailable" }, 503);

  if (!body.code && existing && Date.parse(existing.access_expires_at) > Date.now() + 60_000) return tokens(existing);
  if (body.action === "restore" && !existing) return json({ error: "not_connected" }, 404);

  let lock: string | null = null;
  let refreshToken = existing?.refresh_token ?? body.refresh_token;
  if (!body.code && existing) {
    lock = crypto.randomUUID();
    const { data: claimed, error } = await db.rpc("claim_whoop_refresh", { p_user_id: userID, p_lock: lock })
      .maybeSingle<Connection>();
    if (error || !claimed) return json({ error: "refresh_busy" }, 503);
    refreshToken = claimed.refresh_token ?? undefined;
  }
  try {
    const form = new URLSearchParams({ client_id: clientID, client_secret: clientSecret });
    if (body.code && body.redirect_uri) {
      form.set("grant_type", "authorization_code");
      form.set("code", body.code);
      form.set("redirect_uri", body.redirect_uri);
      if (body.verifier) form.set("code_verifier", body.verifier);
    } else if (refreshToken) {
      form.set("grant_type", "refresh_token");
      form.set("refresh_token", refreshToken);
      form.set("scope", "offline");
    } else { return json({ error: "connection_expired", status: 401 }, 400); }

    const response = await fetch(WHOOP_TOKEN_URL, {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form, signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) {
      // Never log the provider's body: OAuth errors can echo credentials.
      console.error(`whoop token request failed: ${response.status}`);
      return json({ error: "exchange_failed", status: response.status }, 502);
    }
    const issued = await response.json();
    if (typeof issued.access_token !== "string") return json({ error: "invalid_upstream_response" }, 502);
    const row = { user_id: userID, access_token: issued.access_token,
      refresh_token: issued.refresh_token ?? refreshToken ?? null,
      access_expires_at: new Date(Date.now() + (issued.expires_in ?? 3600) * 1000).toISOString(),
      refresh_lock: null, refresh_locked_until: null, updated_at: new Date().toISOString() };
    // A late refresh cannot resurrect a removed or newly reconnected row.
    const result = lock
      ? await db.from("whoop_connections").update(row).eq("user_id", userID).eq("refresh_lock", lock).select("user_id")
      : await db.from("whoop_connections").upsert(row).select("user_id");
    if (result.error || !result.data?.length) return json({ error: "could_not_save_connection" }, 503);
    return tokens(row);
  } catch {
    return json({ error: "upstream_unavailable" }, 503);
  } finally {
    if (lock) await db.from("whoop_connections").update({ refresh_lock: null, refresh_locked_until: null })
      .eq("user_id", userID).eq("refresh_lock", lock);
  }
});
