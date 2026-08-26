import { callPlaid, json, PlaidError, resolveUser, serviceClient } from "../_shared/plaid.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let body: { public_token?: string; institution_id?: string; institution_name?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!body.public_token) return json({ error: "missing_public_token" }, 400);

  const db = serviceClient();

  // Connecting the same bank twice creates two Items with overlapping
  // transactions under different transaction ids, which the device cannot
  // deduplicate. Refuse before spending the exchange.
  if (body.institution_id) {
    const { data: existing } = await db
      .from("plaid_items")
      .select("item_id")
      .eq("user_id", userID)
      .eq("institution_id", body.institution_id)
      .maybeSingle();
    if (existing) return json({ error: "institution_already_connected" }, 409);
  }

  try {
    const exchanged = await callPlaid("/item/public_token/exchange", {
      public_token: body.public_token,
    });

    const { error } = await db.from("plaid_items").insert({
      user_id: userID,
      item_id: exchanged.item_id,
      access_token: exchanged.access_token,
      institution_id: body.institution_id ?? null,
      institution_name: body.institution_name ?? "Bank",
    });
    if (error) {
      // Never log the row: it holds the credential.
      console.error(`plaid item insert failed: ${error.code}`);
      return json({ error: "storage_failed" }, 500);
    }

    // The access token stops here. The device gets only what it needs to
    // render the connection.
    return json({
      item_id: exchanged.item_id,
      institution_name: body.institution_name ?? "Bank",
    }, 200);
  } catch (error) {
    const kind = error instanceof PlaidError ? error.kind : "upstream_failure";
    return json({ error: kind }, 502);
  }
});
