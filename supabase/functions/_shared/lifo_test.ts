import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  classifyOpenAIFailure,
  DAILY_TOKEN_CAP,
  LifoRefusal,
  openAIBody,
  parseOutput,
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
