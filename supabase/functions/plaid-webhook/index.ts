// Where Plaid says "this bank has something new".
//
// Plaid calls this when an item has new or changed transactions, or its login
// breaks or is repaired. The function wakes the owner's phones with a silent
// push and does nothing else: it never calls /transactions/sync and never
// sees a transaction. The phone syncs through plaid-sync as it always has,
// so the ledger still lives only on the device.
//
// Deployed with verify_jwt = false because Plaid has no Supabase session.
// The Plaid signature takes its place, and is checked before the body is
// trusted for anything. See _shared/plaid_webhook.ts.
//
// Configure with:
//
//   supabase secrets set PLAID_WEBHOOK_URL=https://<project>.supabase.co/functions/v1/plaid-webhook

import { apnsConfigFromEnv, sendPush } from "../_shared/apns.ts";
import { callPlaid, json, serviceClient } from "../_shared/plaid.ts";
import {
  type PlaidJWK,
  silentSyncPayload,
  verifyPlaidWebhook,
  webhookAction,
} from "../_shared/plaid_webhook.ts";

// Plaid rotates keys rarely; one fetch per key per warm instance is plenty.
const keys = new Map<string, PlaidJWK>();

async function fetchKey(kid: string): Promise<PlaidJWK | null> {
  const known = keys.get(kid);
  if (known) return known;
  try {
    const result = await callPlaid("/webhook_verification_key/get", { key_id: kid });
    const key = result.key as PlaidJWK | undefined;
    if (!key) return null;
    keys.set(kid, key);
    return key;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const raw = await req.text();
  const verdict = await verifyPlaidWebhook(raw, req.headers.get("Plaid-Verification"), new Date(), fetchKey);
  if (!verdict.ok) {
    console.error(`plaid webhook rejected: ${verdict.reason}`);
    return json({ error: "unverified" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  // Anything verified gets a 200, acted on or not: Plaid retries a non-200,
  // and a webhook we chose to ignore is not a failure worth retrying.
  if (webhookAction(body) !== "sync" || typeof body.item_id !== "string") {
    return json({ ok: true, woke: 0 }, 200);
  }

  const apns = apnsConfigFromEnv();
  if (!apns) return json({ ok: true, woke: 0 }, 200);

  const db = serviceClient();
  const { data: item, error: itemError } = await db
    .from("plaid_items")
    .select("user_id")
    .eq("item_id", body.item_id)
    .maybeSingle();
  if (itemError) {
    console.error(`plaid webhook item lookup failed: ${itemError.code}`);
    return json({ error: "storage_failed" }, 500);
  }
  // A disconnected bank whose webhook was still in flight.
  if (!item) return json({ ok: true, woke: 0 }, 200);

  const { data: tokens, error: tokenError } = await db
    .from("device_tokens")
    .select("token")
    .eq("user_id", item.user_id);
  if (tokenError) {
    console.error(`plaid webhook token lookup failed: ${tokenError.code}`);
    return json({ error: "storage_failed" }, 500);
  }

  const now = new Date();
  let woke = 0;
  for (const { token } of tokens ?? []) {
    const result = await sendPush(apns, token, silentSyncPayload(), now, "background");
    if (result.unregistered) await db.from("device_tokens").delete().eq("token", token);
    else if (result.status < 300) woke += 1;
  }
  return json({ ok: true, woke }, 200);
});
