// Shared Plaid plumbing.
//
// These functions exist for exactly one reason: every Plaid endpoint requires
// client_id and secret on the request, and an .ipa is a zip file, so a secret
// compiled into the app is public the moment it ships. The device therefore
// cannot call Plaid at all and calls these instead.
//
// Set the secrets with:
//
//   supabase secrets set PLAID_CLIENT_ID=... PLAID_SECRET=... PLAID_ENV=sandbox
//
// PLAID_ENV is what sequences the work: build and test the whole path against
// sandbox and its fake institutions, then flip this one value to reach a real
// bank. The secret is never logged, never returned, and never written to this
// repository.

export { json, resolveUser, serviceClient } from "./supabase.ts";

const HOSTS: Record<string, string> = {
  sandbox: "https://sandbox.plaid.com",
  production: "https://production.plaid.com",
};

export function plaidConfig() {
  const clientID = Deno.env.get("PLAID_CLIENT_ID");
  const secret = Deno.env.get("PLAID_SECRET");
  const env = Deno.env.get("PLAID_ENV") ?? "sandbox";
  const host = HOSTS[env];
  // Deliberately does not say which one is missing.
  if (!clientID || !secret || !host) return null;
  return { clientID, secret, host };
}

export type PlaidFailure = "item_login_required" | "rate_limited" | "upstream_failure";

// Plaid is not obliged to send JSON when it is having a bad day.
function plaidErrorCode(body: string): string {
  try {
    return (JSON.parse(body)?.error_code ?? "") as string;
  } catch {
    return "";
  }
}

/// An expired bank login needs a reconnect prompt, not a retry spinner, so it
/// gets its own code. A rate limit is worth retrying later. Everything else is
/// opaque on purpose: Plaid's error bodies echo request parameters.
export function classifyPlaidFailure(status: number, body: string): PlaidFailure {
  const code = plaidErrorCode(body);
  if (code === "ITEM_LOGIN_REQUIRED") return "item_login_required";
  if (status === 429 || code === "RATE_LIMIT_EXCEEDED") return "rate_limited";
  return "upstream_failure";
}

export class PlaidError extends Error {
  // `code` is Plaid's raw error_code, kept alongside the coarse `kind` for the
  // rare caller that needs to distinguish within a kind (plaid-disconnect
  // telling ITEM_NOT_FOUND apart from every other upstream_failure). Adding a
  // PlaidFailure kind for every such case would force every other caller to
  // handle a bucket it doesn't care about, so this stays a narrow escape hatch
  // instead.
  constructor(public kind: PlaidFailure, public status: number, public code = "") {
    super(kind);
  }
}

export async function callPlaid(
  path: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const config = plaidConfig();
  if (!config) throw new PlaidError("upstream_failure", 500);

  const response = await fetch(`${config.host}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      ...body,
      client_id: config.clientID,
      secret: config.secret,
    }),
  });

  const text = await response.text();
  if (!response.ok) {
    // Logged with the body so the cause is visible in function logs, while the
    // client receives only a kind, because Plaid's errors echo request
    // parameters. The request body is never logged: it holds the secret.
    console.error(`plaid ${path} failed: ${response.status} ${text.slice(0, 300)}`);
    throw new PlaidError(
      classifyPlaidFailure(response.status, text),
      response.status,
      plaidErrorCode(text),
    );
  }
  return JSON.parse(text);
}
