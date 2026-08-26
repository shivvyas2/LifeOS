import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";
import {
  classifyOpenAIFailure,
  DAILY_TOKEN_CAP,
  LifoRefusal,
  openAIBody,
  parseOutput,
  taskConfig,
} from "../_shared/lifo.ts";

// The context bundle in `prompt` is used for this one completion and
// discarded. It is never written to a table and never logged; log lines
// carry ids, task names, token counts, and latency only.
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json({ error: "server_not_configured" }, 500);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let task = "", prompt = "";
  try {
    const body = await req.json();
    task = String(body.task ?? "");
    prompt = String(body.prompt ?? "");
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!taskConfig(task) || !prompt) return json({ error: "unknown_task" }, 400);

  const db = serviceClient();
  const { data: usage, error: usageError } = await db
    .from("lifo_usage")
    .select("tokens")
    .eq("user_id", userID)
    .eq("day", new Date().toISOString().slice(0, 10))
    .maybeSingle();
  if (usageError) {
    console.error(`lifo usage lookup failed: ${usageError.code}`);
    return json({ error: "storage_failed" }, 500);
  }
  if ((usage?.tokens ?? 0) >= DAILY_TOKEN_CAP) return json({ error: "exhausted" }, 429);

  const started = Date.now();
  let reply: Response;
  try {
    reply = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(openAIBody(task, prompt)),
    });
  } catch {
    // DNS, timeout, connection reset: no billable call happened, so nothing
    // to debit. Logged with a coarse reason only; never the prompt, never
    // the key.
    console.error(`lifo openai fetch failed`);
    return json({ error: "upstream_failure" }, 502);
  }
  if (!reply.ok) {
    console.error(`lifo openai failed status=${reply.status}`);
    return json({ error: classifyOpenAIFailure(reply.status) }, 502);
  }

  const body = await reply.json();
  const tokens = (body as { usage?: { total_tokens?: number } })?.usage
    ?.total_tokens ?? 0;
  // We charge for what the provider billed us for, not only for what we
  // could use. A refusal or a malformed reply still consumed real OpenAI
  // tokens; leaving those unmetered would let a user burn unlimited budget
  // for free simply by asking off-topic questions in a loop. So this debit
  // runs on every path that reaches here (success, refusal, and parse
  // failure alike), before we even know whether the reply parses. The
  // debit's own failure stays non-fatal to the response.
  const { error: debitError } = await db.rpc("lifo_debit", {
    p_user: userID,
    p_tokens: tokens,
  });
  if (debitError) console.error(`lifo debit failed: ${debitError.code}`);

  try {
    const { output } = parseOutput(task, body);
    console.log(
      `lifo task=${task} tokens=${tokens} ms=${Date.now() - started}`,
    );
    return json({ output, tokens }, 200);
  } catch (failure) {
    if (failure instanceof LifoRefusal) {
      return json({ error: "refused", message: failure.message }, 403);
    }
    console.error(`lifo parse failed`);
    return json({ error: "upstream_failure" }, 502);
  }
});
