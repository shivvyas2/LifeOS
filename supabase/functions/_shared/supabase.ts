// Generic Supabase plumbing shared across every Edge Function: resolving the
// calling user from their own token, building the service-role client, and
// the small JSON response helper. Nothing here is specific to any one
// integration; a module named for one integration (plaid.ts, lifo.ts, ...)
// must not be the front door for another.

import { createClient } from "jsr:@supabase/supabase-js@2";

/// Resolves the caller from their own token.
///
/// This is a security boundary, not a formality. Every one of these functions
/// reads a bank credential keyed by user, so a service-role client that
/// trusted a user_id from the request body would let any signed-in user pull
/// anyone else's transactions.
export async function resolveUser(req: Request): Promise<string | null> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return null;

  const client = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

/// The service-role client. Only ever used after `resolveUser` has returned an
/// id, and only ever scoped to that id.
export function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

export function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
