// Live checks against the real provider, for the request shapes the unit
// tests can only assert the structure of. Skipped unless a key is granted, so
// a plain `deno test` stays offline and free. To run (a few cents a run):
//
//   ANTHROPIC_API_KEY=... deno test --allow-env --allow-net _shared/lifo_live_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import Anthropic from "npm:@anthropic-ai/sdk@0.131.0";
import { chatBody, parseChatReply, parseOutput, parseStreamEvent, taskBody } from "./lifo.ts";

const granted =
  Deno.permissions.querySync({ name: "env", variable: "ANTHROPIC_API_KEY" }).state === "granted" &&
  Deno.permissions.querySync({ name: "net", host: "api.anthropic.com" }).state === "granted";
const apiKey = granted ? Deno.env.get("ANTHROPIC_API_KEY") : undefined;
const live = (name: string, fn: (client: Anthropic) => Promise<void>) =>
  Deno.test({ name: `live: ${name}`, ignore: !apiKey, fn: () => fn(new Anthropic({ apiKey })) });

live("a one-shot task comes back in its schema", async (client) => {
  const reply = await client.messages.create(
    taskBody("nudge", "Trigger: steps down. This week 4,100 a day; last week 7,900 a day."),
  );
  const { output, tokens } = parseOutput("nudge", reply);
  assertEquals(typeof output.text, "string");
  assertEquals(tokens > 0, true);
});

live("a streamed chat turn delivers text and usage", async (client) => {
  const events = await client.messages.create({
    ...chatBody([{ role: "user", content: "How did I sleep this week?" }], [], "Sleep, last 7 nights: 6h10m average."),
    stream: true,
  });
  let text = "";
  let sawUsage = false;
  for await (const event of events) {
    const parsed = parseStreamEvent(event);
    if (parsed.delta) text += parsed.delta;
    if (parsed.usage) sawUsage = true;
  }
  assertEquals(text.length > 0, true);
  assertEquals(sawUsage, true);
});

// The one shape the translation layer cannot prove offline: a tool round trip
// replayed from the device's flat format, which carries no thinking blocks.
live("a tool round trip in the device's format is accepted", async (client) => {
  const tool = {
    type: "function",
    function: {
      name: "get_events",
      description: "Lists calendar events for a day.",
      parameters: { type: "object", properties: { day: { type: "string" } }, required: ["day"] },
    },
  };
  const thread: Record<string, unknown>[] = [{ role: "user", content: "What is on my calendar on 2026-10-05? Use the tool." }];
  const first = parseChatReply(await client.messages.create(chatBody(thread, [tool], "Today is 2026-10-03.")));
  assertEquals(first.kind, "tool_calls");
  if (first.kind !== "tool_calls") return;

  thread.push({ role: "assistant", content: "", tool_calls: first.toolCalls });
  for (const call of first.toolCalls) {
    thread.push({ role: "tool", tool_call_id: call.id, content: "One event: dentist at 09:30." });
  }
  const second = parseChatReply(await client.messages.create(chatBody(thread, [tool], "Today is 2026-10-03.")));
  assertEquals(second.kind, "text");
});
