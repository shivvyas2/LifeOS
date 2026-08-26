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
    .select("item_id, access_token, institution_name")
    .eq("user_id", userID);

  if (error) {
    console.error(`plaid item lookup failed: ${error.code}`);
    return json({ error: "storage_failed" }, 500);
  }

  const items = [];
  for (const row of rows ?? []) {
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
      });
    }
  }

  return json({ items }, 200);
});

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
  // for a reason that has nothing to do with them.
  let accounts: unknown[] = [];
  try {
    const balances = await callPlaid("/accounts/balance/get", {
      access_token: row.access_token,
    });
    accounts = (balances.accounts as unknown[]) ?? [];
  } catch (failure) {
    const kind = failure instanceof PlaidError ? failure.kind : "upstream_failure";
    console.error(`plaid balance fetch failed for item: ${kind}`);
  }

  return {
    item_id: row.item_id,
    institution_name: row.institution_name,
    added, modified, removed,
    accounts,
    next_cursor: nextCursor,
    has_more: hasMore,
    error: null,
  };
}
