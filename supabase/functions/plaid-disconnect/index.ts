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
  const { data: row } = await db
    .from("plaid_items")
    .select("access_token")
    .eq("user_id", userID)
    .eq("item_id", itemID)
    .maybeSingle();

  if (!row) return json({ error: "not_found" }, 404);

  try {
    await callPlaid("/item/remove", { access_token: row.access_token });
  } catch (error) {
    // Plaid refusing the removal must not strand the row. A connected Item
    // bills monthly, so the local record going and the remote staying is the
    // worse failure: the user would have no way left to reach it.
    const kind = error instanceof PlaidError ? error.kind : "upstream_failure";
    console.error(`plaid item remove failed: ${kind}`);
  }

  await db.from("plaid_items").delete().eq("user_id", userID).eq("item_id", itemID);
  return json({ ok: true }, 200);
});
