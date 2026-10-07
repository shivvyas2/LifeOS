import Anthropic from "npm:@anthropic-ai/sdk@0.131.0";
import { json, resolveUser, serviceClient } from "../_shared/supabase.ts";
import {
  billedTokens,
  chatBody,
  classifyFailure,
  DAILY_TOKEN_CAP,
  LifoRefusal,
  mergeUsage,
  parseChatReply,
  parseOutput,
  parseRequest,
  parseStreamEvent,
  taskBody,
  withoutTuning,
} from "../_shared/lifo.ts";

// The context bundle in `prompt` is used for this one completion and
// discarded. It is never written to a table and never logged; log lines
// carry ids, task names, token counts, and latency only.
/// Re-emits the provider's stream as our own, in our own shape.
///
/// Deliberately not a pass-through of the provider's events. The client
/// would then have to know the provider's event format, which is the one
/// thing this function exists to keep it from knowing: swapping providers
/// would become a client release. What crosses the wire is `{"delta": "..."}`
/// and nothing else, closed by `[DONE]`.
///
/// The debit runs after the last event, because the output side of usage
/// only arrives there. A client that walks away half way does not stop the
/// read: the rest of the stream is drained unseen so the debit is the real
/// one, and a walked-away-from answer is still paid for.
function streamToClient(
  events: AsyncIterable<Anthropic.RawMessageStreamEvent>,
  debit: (tokens: number) => Promise<void>,
  started: number,
): Response {
  const encoder = new TextEncoder();
  let gone = false;

  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (frame: string) => {
        if (!gone) controller.enqueue(encoder.encode(`data: ${frame}\n\n`));
      };
      let usage: Parameters<typeof billedTokens>[0] = {};
      let characters = 0;
      let refusal = "";
      let failure: unknown = null;

      try {
        for await (const event of events) {
          const parsed = parseStreamEvent(event);
          if (parsed.usage) usage = mergeUsage(usage, parsed.usage);
          if (parsed.refusal) refusal = parsed.refusal;
          if (parsed.delta) {
            characters += parsed.delta.length;
            send(JSON.stringify({ delta: parsed.delta }));
          }
        }
      } catch (error) {
        // The stream broke part way. Whatever was generated up to here was
        // still billed, so the debit below still runs.
        failure = error;
      }

      const tokens = billedTokens(usage);
      console.log(
        `lifo task=chat stream=1 chars=${characters} tokens=${tokens} ms=${Date.now() - started}${
          failure ? " failed=1" : ""
        }`,
      );
      // Never zero in practice, but a provider that omitted usage must not
      // turn into a free path through the cap.
      if (tokens > 0) await debit(tokens);

      if (gone) return;
      if (failure) {
        // Ending with [DONE] would present half an answer as a whole one.
        controller.error(failure);
        return;
      }
      // A refusal is the model declining, which is a different thing from the
      // stream ending, so it is named rather than left as a short answer.
      if (refusal) send(JSON.stringify({ error: "refused", message: refusal }));
      send("[DONE]");
      controller.close();
    },
    cancel() {
      gone = true;
    },
  });

  return new Response(body, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      // Proxies that buffer an event stream defeat the entire point of one.
      "X-Accel-Buffering": "no",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
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
    ? chatBody(parsed.messages, parsed.tools, parsed.context)
    : taskBody(parsed.task, parsed.prompt);

  const started = Date.now();
  const client = new Anthropic({ apiKey });

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

  /// One call to the provider, retried once without the effort setting if it
  /// is rejected outright.
  ///
  /// A 400 is the only status worth retrying here: it is the provider saying
  /// the body is wrong, which is the only failure a smaller body can fix.
  /// Rate limits, overloads and server errors are retried by the SDK itself.
  async function call<T>(send: (body: Anthropic.MessageCreateParamsNonStreaming) => Promise<T>) {
    try {
      return await send(payload);
    } catch (error) {
      if (!(error instanceof Anthropic.BadRequestError)) throw error;
      console.error("lifo provider rejected the tuned body; retrying plain");
      return await send(withoutTuning(payload));
    }
  }

  let reply: Anthropic.Message | null = null;
  let events: AsyncIterable<Anthropic.RawMessageStreamEvent> | null = null;
  try {
    if (streaming) {
      // `create` with `stream: true` rather than `stream()`, because it
      // resolves only once the provider has accepted the request. A rejected
      // request is then an HTTP error code here, before the 200 of an event
      // stream has gone out.
      events = await call((body) => client.messages.create({ ...body, stream: true }));
    } else {
      reply = await call((body) => client.messages.create(body));
    }
  } catch (error) {
    if (error instanceof Anthropic.APIError && error.status !== undefined) {
      console.error(`lifo provider failed status=${error.status}`);
      return json({ error: classifyFailure(error.status) }, 502);
    }
    // DNS, timeout, connection reset: no billable call happened, so nothing
    // to debit. Logged with a coarse reason only; never the prompt, never
    // the key.
    console.error("lifo provider call failed");
    return json({ error: "upstream_failure" }, 502);
  }

  // The streamed path. Text is forwarded as it arrives rather than held until
  // the reply is whole: the wait for a first word is the whole of how fast
  // this feels, and it used to be the wait for the last one.
  if (events) return streamToClient(events, debit, started);
  if (!reply) return json({ error: "upstream_failure" }, 502);

  const tokens = billedTokens(reply.usage);
  // We charge for what the provider billed us for, not only for what we
  // could use. A refusal or a malformed reply still consumed real tokens;
  // leaving those unmetered would let a user burn unlimited budget for free
  // simply by asking off-topic questions in a loop. So this debit runs on
  // every path that reaches here (success, refusal, and parse failure
  // alike), before we even know whether the reply parses. The debit's own
  // failure stays non-fatal to the response.
  await debit(tokens);

  try {
    if (parsed.kind === "chat") {
      const parsedChat = parseChatReply(reply);
      console.log(`lifo task=chat kind=${parsedChat.kind} tokens=${tokens} ms=${Date.now() - started}`);
      return parsedChat.kind === "text"
        ? json({ output: { text: parsedChat.text }, tokens }, 200)
        : json({ tool_calls: parsedChat.toolCalls, tokens }, 200);
    }
    const { output } = parseOutput(parsed.task, reply);
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
