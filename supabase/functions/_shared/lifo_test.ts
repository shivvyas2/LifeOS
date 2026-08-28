import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  chatBody,
  classifyOpenAIFailure,
  DAILY_TOKEN_CAP,
  LifoRefusal,
  openAIBody,
  parseChatReply,
  parseOutput,
  parseRequest,
  taskConfig,
} from "./lifo.ts";

Deno.test("the answer task maps to the mini model with a strict schema", () => {
  const config = taskConfig("answer")!;
  assertEquals(config.model, "gpt-5-mini");
  const schema = config.schema as { name: string; strict: boolean };
  assertEquals(schema.strict, true);
});

// The system prompt is the guardrail. It must live here, server-side, so a
// modified client cannot strip it, and it must actually pin the scope.
Deno.test("the system prompt pins LIFO to this user's own data", () => {
  const system = taskConfig("answer")!.system;
  for (const anchor of ["their own", "decline", "diagnos", "invest"]) {
    assertEquals(system.toLowerCase().includes(anchor), true, `missing: ${anchor}`);
  }
});

Deno.test("an unknown task has no config and no request body", () => {
  assertEquals(taskConfig("exfiltrate"), null);
  assertThrows(() => openAIBody("exfiltrate", "hi"));
});

Deno.test("the request body carries the prompt as the user turn", () => {
  const body = openAIBody("answer", "Question: how did I sleep?") as {
    model: string;
    messages: { role: string; content: string }[];
  };
  assertEquals(body.model, "gpt-5-mini");
  assertEquals(body.messages[0].role, "system");
  assertEquals(body.messages[1], { role: "user", content: "Question: how did I sleep?" });
});

Deno.test("a rate limit is its own kind, because it is worth retrying later", () => {
  assertEquals(classifyOpenAIFailure(429), "rate_limited");
  assertEquals(classifyOpenAIFailure(500), "upstream_failure");
  assertEquals(classifyOpenAIFailure(400), "upstream_failure");
});

Deno.test("a well-formed reply yields the parsed output and the spend", () => {
  const { output, tokens } = parseOutput("answer", {
    choices: [{ message: { content: `{"answer":"You slept 7h12m."}` } }],
    usage: { total_tokens: 812 },
  });
  assertEquals(output, { answer: "You slept 7h12m." });
  assertEquals(tokens, 812);
});

Deno.test("a refusal surfaces as its own error, with the model's words", () => {
  assertThrows(
    () =>
      parseOutput("answer", {
        choices: [{ message: { refusal: "I can't help with that." } }],
        usage: { total_tokens: 40 },
      }),
    LifoRefusal,
    "I can't help with that.",
  );
});

Deno.test("a malformed body throws rather than shipping garbage to the app", () => {
  assertThrows(() => parseOutput("answer", { choices: [] }));
  assertThrows(() =>
    parseOutput("answer", { choices: [{ message: { content: "not json" } }], usage: { total_tokens: 1 } })
  );
});

Deno.test("the cap matches the spec's ceiling arithmetic", () => {
  assertEquals(DAILY_TOKEN_CAP, 150_000);
});

// parseOutput is its own entry point, separate from openAIBody, so it cannot
// assume a caller already validated the task name. Without this guard, an
// unrecognized task would skip shape validation and hand back whatever JSON
// the model returned, unchecked.
Deno.test("an unknown task name throws rather than returning unvalidated JSON", () => {
  assertThrows(() =>
    parseOutput("exfiltrate", {
      choices: [{ message: { content: `{"anything":"goes"}` } }],
      usage: { total_tokens: 1 },
    })
  );
});

// Validation must be derived from the task's own schema, not a hardcoded
// field name, so a reply that is well-formed JSON but missing a
// schema-required property is still rejected rather than passed through.
Deno.test("a reply missing a schema-required property throws", () => {
  assertThrows(() =>
    parseOutput("answer", {
      choices: [{ message: { content: `{}` } }],
      usage: { total_tokens: 1 },
    })
  );
});

// The schema declares a type for each required property, not just its
// presence. A reply that has the key but the wrong type is exactly the kind
// of wrong-shaped output a hardcoded check would have let through.
Deno.test("a reply whose required property has the wrong type throws", () => {
  assertThrows(() =>
    parseOutput("answer", {
      choices: [{ message: { content: `{"answer":123}` } }],
      usage: { total_tokens: 1 },
    })
  );
});

Deno.test("the chat task still carries the scope guardrail", () => {
  const system = taskConfig("chat")!.system;
  for (const anchor of ["their own", "decline", "diagnos", "invest"]) {
    assertEquals(system.toLowerCase().includes(anchor), true, `missing: ${anchor}`);
  }
});

// The whole point of the slice. If this drifts back to the one-shot
// instruction, LIFO goes back to being a box that answers and stops.
Deno.test("the chat task is allowed to be conversational", () => {
  const system = taskConfig("chat")!.system.toLowerCase();
  assertEquals(system.includes("earlier"), true);
  assertEquals(system.includes("one question"), true);
});

Deno.test("the chat body sends the thread behind the system prompt", () => {
  const body = chatBody(
    [{ role: "user", content: "how did I sleep?" }],
    [],
  ) as { model: string; messages: { role: string }[]; tools?: unknown[] };
  assertEquals(body.model, "gpt-5-mini");
  assertEquals(body.messages[0].role, "system");
  assertEquals(body.messages[1].role, "user");
});

// An empty tools array and an absent one mean different things to the
// provider, and sending `tools: []` is rejected by some versions outright.
Deno.test("no tools means the key is absent, not empty", () => {
  const body = chatBody([{ role: "user", content: "hi" }], []) as Record<string, unknown>;
  assertEquals("tools" in body, false);
});

Deno.test("tools are passed through with an auto choice", () => {
  const tool = { type: "function", function: { name: "get_events" } };
  const body = chatBody([{ role: "user", content: "hi" }], [tool]) as Record<string, unknown>;
  assertEquals(body.tools, [tool]);
  assertEquals(body.tool_choice, "auto");
});

Deno.test("an assistant tool call is normalised into the shape OpenAI accepts", () => {
  const body = chatBody(
    [{
      role: "assistant",
      content: "",
      tool_calls: [{ id: "call_1", name: "get_events", arguments: '{"start":"2026-08-28"}' }],
    }],
    [],
  ) as { messages: Record<string, unknown>[] };
  const call = (body.messages[1].tool_calls as Record<string, unknown>[])[0];
  assertEquals(call.id, "call_1");
  assertEquals(call.type, "function");
  assertEquals(call.function, { name: "get_events", arguments: '{"start":"2026-08-28"}' });
});

Deno.test("a tool result message is already in OpenAI's shape and is left alone", () => {
  const message = { role: "tool", tool_call_id: "call_1", content: "3 events" };
  const body = chatBody([message], []) as { messages: Record<string, unknown>[] };
  assertEquals(body.messages[1], message);
});

Deno.test("a text completion parses as text", () => {
  const parsed = parseChatReply({
    choices: [{ message: { content: "Six hours." } }],
    usage: { total_tokens: 120 },
  });
  assertEquals(parsed, { kind: "text", text: "Six hours.", tokens: 120 });
});

Deno.test("a tool call completion parses as tool calls", () => {
  const parsed = parseChatReply({
    choices: [{
      message: {
        tool_calls: [{
          id: "call_42",
          function: { name: "get_events", arguments: '{"start":"2026-08-28"}' },
        }],
      },
    }],
    usage: { total_tokens: 90 },
  }) as { kind: string; toolCalls: { id: string; name: string; arguments: string }[] };
  assertEquals(parsed.kind, "tool_calls");
  assertEquals(parsed.toolCalls[0].id, "call_42");
  assertEquals(parsed.toolCalls[0].name, "get_events");
  assertEquals(parsed.toolCalls[0].arguments, '{"start":"2026-08-28"}');
});

Deno.test("a refusal is a refusal on the chat path too", () => {
  assertThrows(
    () => parseChatReply({ choices: [{ message: { refusal: "Not something I cover." } }] }),
    LifoRefusal,
  );
});

// Load-bearing regression guard. Slice 1 must not change how the one-shot
// tasks are served, and this is the test that notices if it did.
Deno.test("the old prompt shape still parses as a prompt request", () => {
  const parsed = parseRequest({ task: "answer", prompt: "Question: how did I sleep?" });
  assertEquals(parsed, {
    kind: "prompt",
    task: "answer",
    prompt: "Question: how did I sleep?",
  });
});

Deno.test("a chat request parses as a chat request", () => {
  const parsed = parseRequest({
    task: "chat",
    messages: [{ role: "user", content: "hi" }],
    tools: [],
  }) as { kind: string; messages: unknown[] };
  assertEquals(parsed.kind, "chat");
  assertEquals(parsed.messages.length, 1);
});

Deno.test("a request naming no known task is refused before any spend", () => {
  assertEquals(parseRequest({ task: "exfiltrate", prompt: "hi" }), null);
  assertEquals(parseRequest({ task: "answer" }), null);
  assertEquals(parseRequest({ task: "chat", messages: [] }), null);
  assertEquals(parseRequest("not an object"), null);
});
