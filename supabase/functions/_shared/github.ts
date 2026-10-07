// The GitHub sign-in's one server step: swapping a code for a token with a
// secret the app cannot hold, and revoking it on Disconnect. Stateless on
// purpose: nothing is stored and no token is logged, so the operator never
// holds anyone's GitHub access.

import { json } from "./supabase.ts";

type Deps = {
  resolveUser: (req: Request) => Promise<string | null>;
  fetch: typeof fetch;
  env: (name: string) => string | undefined;
};

export async function handleGitHubToken(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST" && req.method !== "DELETE") return json({ error: "method_not_allowed" }, 405);
  if (!(await deps.resolveUser(req))) return json({ error: "unauthorized" }, 401);
  const clientID = deps.env("GITHUB_CLIENT_ID");
  const secret = deps.env("GITHUB_CLIENT_SECRET");
  if (!clientID || !secret) return json({ error: "server_not_configured" }, 500);

  let body: { code?: string; verifier?: string; redirect_uri?: string; access_token?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }

  if (req.method === "DELETE") {
    if (!body.access_token) return json({ error: "invalid_body" }, 400);
    const response = await deps.fetch(`https://api.github.com/applications/${clientID}/grant`, {
      method: "DELETE",
      headers: {
        Authorization: `Basic ${btoa(`${clientID}:${secret}`)}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ access_token: body.access_token }),
    });
    // 404 or 422: GitHub no longer knows the token, which is the goal.
    return [204, 404, 422].includes(response.status)
      ? new Response(null, { status: 204 })
      : json({ error: "revoke_failed" }, 502);
  }

  if (!body.code || !body.redirect_uri) return json({ error: "invalid_body" }, 400);
  const form = new URLSearchParams({
    client_id: clientID, client_secret: secret, code: body.code, redirect_uri: body.redirect_uri,
  });
  if (body.verifier) form.set("code_verifier", body.verifier);
  const response = await deps.fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const payload = await response.json().catch(() => ({}));
  if (!payload.access_token) return json({ error: payload.error ?? "exchange_failed" }, 400);
  return json({ access_token: payload.access_token, scope: payload.scope ?? "" }, 200);
}
