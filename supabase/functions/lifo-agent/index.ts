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
  const reply = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(openAIBody(task, prompt)),
  });
  if (!reply.ok) {
    console.error(`lifo openai failed status=${reply.status}`);
    return json({ error: classifyOpenAIFailure(reply.status) }, 502);
  }

  try {
    const { output, tokens } = parseOutput(task, await reply.json());
    // Debit after a successful parse: a reply the app never saw should not
    // spend the day's budget. The window where a crash between reply and
    // debit under-counts is accepted; the cap is a guardrail, not a bill.
    const { error: debitError } = await db.rpc("lifo_debit", {
      p_user: userID,
      p_tokens: tokens,
    });
    if (debitError) console.error(`lifo debit failed: ${debitError.code}`);
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
