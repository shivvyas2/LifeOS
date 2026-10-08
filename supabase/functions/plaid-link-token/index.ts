import { accountFilters, callPlaid, json, linkKind, PlaidError, resolveUser } from "../_shared/plaid.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  // The body is optional: an empty or unreadable one is a bank session.
  let kind = linkKind(undefined);
  try {
    kind = linkKind((await req.json())?.kind);
  } catch {
    // No body.
  }

  try {
    const result = await callPlaid("/link/token/create", {
      // Plaid keys its own rate limits and dashboards on this. Using the
      // Supabase user id keeps the two systems talking about the same person.
      user: { client_user_id: userID },
      client_name: "LifeOS",
      products: ["transactions"],
      country_codes: ["US"],
      language: "en",
      ...accountFilters(kind),
      // Banks that use OAuth send the browser here and the app picks it up.
      // Absent in sandbox, where no institution needs it.
      ...(Deno.env.get("PLAID_REDIRECT_URI")
        ? { redirect_uri: Deno.env.get("PLAID_REDIRECT_URI") }
        : {}),
      // Where Plaid says the bank has something new, so the phone hears about
      // a purchase without waiting to be opened. See plaid-webhook.
      ...(Deno.env.get("PLAID_WEBHOOK_URL")
        ? { webhook: Deno.env.get("PLAID_WEBHOOK_URL") }
        : {}),
    });
    return json({ link_token: result.link_token }, 200);
  } catch (error) {
    const failure = error instanceof PlaidError ? error.kind : "upstream_failure";
    return json({ error: failure }, 502);
  }
});
