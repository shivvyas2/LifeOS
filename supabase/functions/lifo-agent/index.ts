import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";
import {
  chatBody,
  classifyOpenAIFailure,
  DAILY_TOKEN_CAP,
  drainSSE,
  LifoRefusal,
  openAIBody,
  parseChatReply,
  parseOutput,
  parseRequest,
  parseStreamChunk,
  withoutTuning,
} from "../_shared/lifo.ts";

// The context bundle in `prompt` is used for this one completion and
// discarded. It is never written to a table and never logged; log lines
// carry ids, task names, token counts, and latency only.
/// Re-emits the provider's stream as our own, in our own shape.
///
/// Deliberately not a pass-through of OpenAI's frames. The client would then
/// have to know the provider's chunk format, which is the one thing this
/// function exists to keep it from knowing: swapping providers would become a
/// client release. What crosses the wire is `{"delta": "..."}` and nothing
/// else, closed by `[DONE]`.
///
/// The debit runs in `flush`, after the last chunk, because usage only arrives
/// there. A stream the client abandons half way still reaches `flush` when the
/// body is cancelled, so a walked-away-from answer is still paid for.
function streamToClient(
  body: ReadableStream<Uint8Array>,
  debit: (tokens: number) => Promise<void>,
  started: number,
): Response {
  let buffer = "";
  let tokens = 0;
  let characters = 0;
  let refusal = "";

  const relay = new TransformStream<string, string>({
    transform(part, controller) {
      buffer += part;
      const { payloads, rest } = drainSSE(buffer);
      buffer = rest;

      for (const payload of payloads) {
        if (payload === "[DONE]") continue;
        let chunk: unknown;
        try {
          chunk = JSON.parse(payload);
        } catch {
          // A frame we cannot read is skipped rather than fatal: the rest of
          // the sentence is still worth delivering.
          continue;
        }
        const { delta, refusal: refused, tokens: used } = parseStreamChunk(chunk);
        if (used !== undefined) tokens = used;
        if (refused) refusal += refused;
        if (delta) {
          characters += delta.length;
          controller.enqueue(`data: ${JSON.stringify({ delta })}\n\n`);
        }
      }
    },
    async flush(controller) {
      // A refusal is the model declining, which is a different thing from the
      // stream ending, so it is named rather than left as a short answer.
      if (refusal) {
        controller.enqueue(
          `data: ${JSON.stringify({ error: "refused", message: refusal })}\n\n`,
        );
      }
      controller.enqueue("data: [DONE]\n\n");
      console.log(
        `lifo task=chat stream=1 chars=${characters} tokens=${tokens} ms=${Date.now() - started}`,
      );
      // Never zero in practice, but a provider that omitted usage must not
      // turn into a free path through the cap.
      if (tokens > 0) await debit(tokens);
    },
  });

  return new Response(
    body.pipeThrough(new TextDecoderStream()).pipeThrough(relay).pipeThrough(
      new TextEncoderStream(),
    ),
    {
      status: 200,
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        // Proxies that buffer an event stream defeat the entire point of one.
        "X-Accel-Buffering": "no",
      },
    },
  );
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json({ error: "server_not_configured" }, 500);

  const userID = await resolveUser(req);
  if (!userID) return json({ error: "unauthorized" }, 401);

  let parsed: ReturnType<typeof parseRequest>;
  try {
    parsed = parseRequest(await req.json());
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!parsed) return json({ error: "unknown_task" }, 400);

  const db = serviceClient();
  // Scoped to the chat kind. `lifo_usage` is keyed on (user_id, day, kind)
  // since the nudge job got its own allowance, so a day with a nudge on it has
  // two rows and an unscoped maybeSingle() would fail rather than read one.
  // Chat and nudges do not share a budget on purpose: a heavy chat evening
  // must not eat the next morning's nudge.
  const { data: usage, error: usageError } = await db
    .from("lifo_usage")
    .select("tokens")
    .eq("user_id", userID)
    .eq("day", new Date().toISOString().slice(0, 10))
    .eq("kind", "chat")
    .maybeSingle();
  if (usageError) {
    console.error(`lifo usage lookup failed: ${usageError.code}`);
    return json({ error: "storage_failed" }, 500);
  }
  if ((usage?.tokens ?? 0) >= DAILY_TOKEN_CAP) return json({ error: "exhausted" }, 429);

  const streaming = parsed.kind === "chat" && parsed.stream;
  const payload = parsed.kind === "chat"
    ? chatBody(parsed.messages, parsed.tools, parsed.context, streaming)
    : openAIBody(parsed.task, parsed.prompt);

  const started = Date.now();

  /// Debits what the provider billed us for. Shared by both paths below, and
  /// non-fatal by design: a failed debit must not cost the user their answer.
  const debit = async (tokens: number) => {
    const { error } = await db.rpc("lifo_debit", {
      p_user: userID,
      p_tokens: tokens,
      p_kind: "chat",
    });
    if (error) console.error(`lifo debit failed: ${error.code}`);
  };

  /// One call to the provider, retried once without the tuning parameters if
  /// it is rejected outright.
  ///
  /// `reasoning_effort` and `verbosity` are worth having and are not worth an
  /// outage: a model that stops accepting one of them should cost a slower,
  /// wordier answer rather than every answer. A 400 is the only status worth
  /// retrying — it is the provider saying the body is wrong, which is the only
  /// failure a smaller body can fix.
  const callOpenAI = async (): Promise<Response | null> => {
    const send = (body: Record<string, unknown>) =>
      fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
    try {
      const first = await send(payload);
      if (first.status !== 400) return first;
      console.error("lifo openai rejected the tuned body; retrying plain");
      return await send(withoutTuning(payload));
    } catch {
      // DNS, timeout, connection reset: no billable call happened, so nothing
      // to debit. Logged with a coarse reason only; never the prompt, never
      // the key.
      console.error(`lifo openai fetch failed`);
      return null;
    }
  };

  const reply = await callOpenAI();
  if (!reply) return json({ error: "upstream_failure" }, 502);
  if (!reply.ok) {
    console.error(`lifo openai failed status=${reply.status}`);
    return json({ error: classifyOpenAIFailure(reply.status) }, 502);
  }

  // The streamed path. Text is forwarded as it arrives rather than held until
  // the reply is whole: the wait for a first word is the whole of how fast
  // this feels, and it used to be the wait for the last one.
  if (streaming && reply.body) {
    return streamToClient(reply.body, debit, started);
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
  await debit(tokens);

  try {
    if (parsed.kind === "chat") {
      // Not `reply`: that name is taken by the provider's Response above, and
      // shadowing it here reads as though this were the same object.
      const parsedChat = parseChatReply(body);
      console.log(`lifo task=chat kind=${parsedChat.kind} tokens=${tokens} ms=${Date.now() - started}`);
      return parsedChat.kind === "text"
        ? json({ output: { text: parsedChat.text }, tokens }, 200)
        : json({ tool_calls: parsedChat.toolCalls, tokens }, 200);
    }
    const { output } = parseOutput(parsed.task, body);
    console.log(`lifo task=${parsed.task} tokens=${tokens} ms=${Date.now() - started}`);
    return json({ output, tokens }, 200);
  } catch (failure) {
    if (failure instanceof LifoRefusal) {
      return json({ error: "refused", message: failure.message }, 403);
    }
    console.error(`lifo parse failed`);
    return json({ error: "upstream_failure" }, 502);
  }
});
