import { callPlaid, json, PlaidError, resolveUser, serviceClient } from "../_shared/plaid.ts";

// An initial pull can be years of history. Three pages per invocation keeps
// the function inside its wall clock; the device sees has_more and calls again.
const MAX_PAGES = 3;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let cursors: Record<string, string> = {};
  try {
    cursors = (await req.json())?.cursors ?? {};
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const db = serviceClient();
  const { data: rows, error } = await db
    .from("plaid_items")
    .select("item_id, access_token, institution_name, webhook_url")
    .eq("user_id", userID);

  if (error) {
    console.error(`plaid item lookup failed: ${error.code}`);
    return json({ error: "storage_failed" }, 500);
  }

  const items = [];
  for (const row of rows ?? []) {
    await adoptWebhook(db, row);
    // One expired bank login must not fail the sync for every other bank, so
    // a per-item failure is reported in the item rather than thrown.
    try {
      items.push(await syncItem(row, cursors[row.item_id]));
    } catch (failure) {
      const kind = failure instanceof PlaidError ? failure.kind : "upstream_failure";
      items.push({
        item_id: row.item_id,
        institution_name: row.institution_name,
        added: [], modified: [], removed: [], accounts: [],
        next_cursor: null, has_more: false,
        error: kind,
        balance_error: null,
      });
    }
  }

  return json({ items }, 200);
});

/// Points a bank connected before webhooks existed at plaid-webhook, once.
///
/// Items carry the webhook URL they were linked with, and every connection
/// made before PLAID_WEBHOOK_URL was set has none. Rather than a one-off
/// script, the next ordinary sync moves each one over and records it, so a
/// changed URL is picked up the same way. A failure is logged and retried on
/// the next sync; it never blocks the sync itself.
async function adoptWebhook(
  db: ReturnType<typeof serviceClient>,
  row: { item_id: string; access_token: string; webhook_url: string | null },
) {
  const url = Deno.env.get("PLAID_WEBHOOK_URL");
  if (!url || row.webhook_url === url) return;
  try {
    await callPlaid("/item/webhook/update", { access_token: row.access_token, webhook: url });
    await db.from("plaid_items").update({ webhook_url: url }).eq("item_id", row.item_id);
  } catch (failure) {
    const kind = failure instanceof PlaidError ? failure.kind : "upstream_failure";
    console.error(`plaid webhook update failed for item: ${kind}`);
  }
}

async function syncItem(
  row: { item_id: string; access_token: string; institution_name: string },
  cursor: string | undefined,
) {
  const added = [], modified = [], removed = [];
  let nextCursor = cursor ?? null;
  let hasMore = true;
  let pages = 0;

  while (hasMore && pages < MAX_PAGES) {
    const page = await callPlaid("/transactions/sync", {
      access_token: row.access_token,
      ...(nextCursor ? { cursor: nextCursor } : {}),
    });
    added.push(...(page.added as unknown[] ?? []));
    modified.push(...(page.modified as unknown[] ?? []));
    removed.push(...(page.removed as unknown[] ?? []));
    nextCursor = page.next_cursor as string;
    hasMore = page.has_more as boolean;
    pages += 1;
  }

  // Balances are refreshed opportunistically. A failure here must not discard
  // transaction pages already fetched: the device would re-fetch them next sync
  // for a reason that has nothing to do with them. But /transactions/sync
  // serves cached data and succeeds even with an expired bank login, while this
  // call does a live fetch and is the one that actually throws
  // ITEM_LOGIN_REQUIRED. That kind still needs to reach the device to raise the
  // reconnect banner, so it travels separately from `error` instead of being
  // swallowed with it.
  let accounts: unknown[] = [];
  let balanceError: string | null = null;
  try {
    const balances = await callPlaid("/accounts/balance/get", {
      access_token: row.access_token,
    });
    accounts = (balances.accounts as unknown[]) ?? [];
  } catch (failure) {
    const kind = failure instanceof PlaidError ? failure.kind : "upstream_failure";
    console.error(`plaid balance fetch failed for item: ${kind}`);
    balanceError = kind;
  }

  return {
    item_id: row.item_id,
    institution_name: row.institution_name,
    added, modified, removed,
    accounts,
    next_cursor: nextCursor,
    has_more: hasMore,
    error: null,
    balance_error: balanceError,
  };
}
