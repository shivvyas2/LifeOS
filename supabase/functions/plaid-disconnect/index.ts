import { callPlaid, json, PlaidError, resolveUser, serviceClient } from "../_shared/plaid.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let itemID: string | undefined;
  try {
    itemID = (await req.json())?.item_id;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!itemID) return json({ error: "missing_item_id" }, 400);

  const db = serviceClient();
  const { data: row, error: lookupError } = await db
    .from("plaid_items")
    .select("access_token")
    .eq("user_id", userID)
    .eq("item_id", itemID)
    .maybeSingle();

  // A failed lookup must not read as "no such connection". That would let the
  // device delete its local record while the Item is still live and still
  // billing, which is exactly the stranding this function exists to prevent.
  if (lookupError) {
    console.error(`plaid item lookup failed: ${lookupError.code}`);
    return json({ error: "storage_failed" }, 500);
  }
  if (!row) return json({ error: "not_found" }, 404);

  // An Item that still exists at Plaid keeps billing, so the local record is
  // the only handle left for retrying the disconnect. It stays until the
  // remote side is really gone: either /item/remove succeeded, or Plaid says
  // there is nothing left to remove.
  try {
    await callPlaid("/item/remove", { access_token: row.access_token });
  } catch (error) {
    const alreadyGone = error instanceof PlaidError && error.code === "ITEM_NOT_FOUND";
    if (!alreadyGone) {
      const kind = error instanceof PlaidError ? error.kind : "upstream_failure";
      console.error(`plaid item remove failed: ${kind}`);
      return json({ error: kind }, 502);
    }
  }

  await db.from("plaid_items").delete().eq("user_id", userID).eq("item_id", itemID);
  return json({ ok: true }, 200);
});
