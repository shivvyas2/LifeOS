// The server side of LIFO's brain: model choice, guardrails, schema, and
// reply parsing. Pure functions only, so every decision here is testable
// without a network. index.ts owns the door (auth, budget, fetch).

export const DAILY_TOKEN_CAP = 150_000;

export class LifoRefusal extends Error {}

// The guardrail prompt lives here, not on the device: a client cannot strip
// what it never carries. Task-specific instructions ride behind it.
const SCOPE = `You are LIFO, a personal life coach inside the LifeOS app.
You coach one person using only their own data, which arrives in the prompt:
health metrics, sleep, workouts, money, and life-sector scores.
Stay on that scope. Decline requests unrelated to coaching this person over
their own data (essays, code, general world knowledge) and redirect to what
their data shows. Never give medical diagnoses; describe patterns and suggest
talking to a professional where it matters. Never recommend specific
investments or securities; keep money talk at budgeting and pattern level.
Cite only numbers that appear in the data given to you; never invent one.`;

const TASKS: Record<string, { model: string; system: string; schema: Record<string, unknown> }> = {
  answer: {
    model: "gpt-5-mini",
    system: `${SCOPE}

Answer the user's question in one short, direct paragraph. No preamble,
no restating the question.`,
    schema: {
      name: "coach_answer",
      strict: true,
      schema: {
        type: "object",
        properties: { answer: { type: "string" } },
        required: ["answer"],
        additionalProperties: false,
      },
    },
  },
};

const CONVERSATION = `Write in plain sentences, the way a person speaks.
Never use markdown: no asterisks, underscores, backticks, hash headings,
bullet characters or numbered lists. Never use em dashes or en dashes; use
a comma or start a new sentence. Give figures as figures with their units,
and never invent one.

You are in a conversation, not answering a form. You may refer back to what
was said earlier in this thread, and you may acknowledge what the person
told you before answering. When you genuinely need something to answer well,
ask one question back. One, not a list, and not out of habit.`;

// The chat task. SCOPE first and always: the guardrail is the reason this
// prompt lives on the server, and the conversational permissions are added
// behind it rather than in place of it.
TASKS.chat = {
  model: "gpt-5-mini",
  system: `${SCOPE}\n\n${CONVERSATION}`,
  schema: TASKS.answer.schema,
};

export function taskConfig(task: string) {
  return TASKS[task] ?? null;
}

export function openAIBody(task: string, prompt: string): Record<string, unknown> {
  const config = taskConfig(task);
  if (!config) throw new Error(`unknown task: ${task}`);
  return {
    model: config.model,
    messages: [
      { role: "system", content: config.system },
      { role: "user", content: prompt },
    ],
    response_format: { type: "json_schema", json_schema: config.schema },
  };
}

export function classifyOpenAIFailure(status: number): "rate_limited" | "upstream_failure" {
  return status === 429 ? "rate_limited" : "upstream_failure";
}

// Validates the parsed reply against the task's own schema, rather than a
// literal field name, so a later task with a different output shape is
// checked against its real schema instead of being rubber-stamped by one
// written for "answer". Only handles the property types this project's
// schemas actually declare (string); anything else throws loudly, so a
// future schema addition can't silently skip validation.
function validateShape(schema: Record<string, unknown>, output: Record<string, unknown>): void {
  const inner = schema.schema as {
    properties?: Record<string, { type?: string }>;
    required?: string[];
  };
  const required = inner.required ?? [];
  const properties = inner.properties ?? {};
  for (const key of required) {
    const declaredType = properties[key]?.type;
    const value = output[key];
    if (declaredType === "string") {
      if (typeof value !== "string") {
        throw new Error(`output missing required property "${key}"`);
      }
    } else {
      throw new Error(`unsupported schema type "${declaredType}" for property "${key}"`);
    }
  }
}

export function parseOutput(
  task: string,
  body: unknown,
): { output: Record<string, unknown>; tokens: number } {
  const config = taskConfig(task);
  if (!config) throw new Error(`unknown task: ${task}`);

  const reply = body as {
    choices?: { message?: { content?: string; refusal?: string } }[];
    usage?: { total_tokens?: number };
  };
  const message = reply.choices?.[0]?.message;
  if (!message) throw new Error("no choices in reply");
  if (message.refusal) throw new LifoRefusal(message.refusal);
  if (!message.content) throw new Error("empty content");
  const output = JSON.parse(message.content) as Record<string, unknown>;
  validateShape(config.schema, output);
  return { output, tokens: reply.usage?.total_tokens ?? 0 };
}

// The device's own wire format keeps tool_calls flat: {id, name, arguments}.
// That is our format, not OpenAI's; the phone never learns OpenAI's message
// schema, matching how parseChatReply already hands tool calls back flat.
// OpenAI's chat completions API requires the nested {id, type, function}
// shape, so this is the seam that translates outbound, right before the
// request leaves for the provider. Everything else, including a tool result
// message ({role: "tool", tool_call_id, content}), is already in OpenAI's
// shape and passes through untouched.
function toOpenAIMessage(message: unknown): unknown {
  if (typeof message !== "object" || message === null) return message;
  const raw = message as Record<string, unknown>;
  if (!Array.isArray(raw.tool_calls)) return message;
  return {
    ...raw,
    tool_calls: raw.tool_calls.map((call: unknown) => {
      if (typeof call !== "object" || call === null || !("name" in call)) return call;
      const flat = call as { id: string; name: string; arguments: string };
      return {
        id: flat.id,
        type: "function",
        function: { name: flat.name, arguments: flat.arguments },
      };
    }),
  };
}

// `context` is the device's rendered view of the user's own data, or the
// calendar assistant's rules and the current date. It arrives in a field of
// its own, never as a message, and it is placed here: a system message
// behind SCOPE. Order is the point. SCOPE stays first so the guardrail is
// never displaced by anything the client sent, and the context sits behind
// it because the model is told to cite only numbers it was given, which
// requires actually giving it some.
export function chatBody(
  messages: unknown[],
  tools: unknown[],
  context = "",
): Record<string, unknown> {
  const system = [{ role: "system", content: TASKS.chat.system }];
  if (context) system.push({ role: "system", content: context });

  const body: Record<string, unknown> = {
    model: TASKS.chat.model,
    messages: [
      ...system,
      ...messages.map(toOpenAIMessage),
    ],
  };
  // Absent rather than empty. The two are not the same to the provider, and
  // an empty array is rejected outright by some versions.
  if (tools.length > 0) {
    body.tools = tools;
    body.tool_choice = "auto";
  }
  return body;
}

export function parseChatReply(body: unknown) {
  const reply = body as {
    choices?: {
      message?: {
        content?: string;
        refusal?: string;
        tool_calls?: { id: string; function: { name: string; arguments: string } }[];
      };
    }[];
    usage?: { total_tokens?: number };
  };
  const message = reply.choices?.[0]?.message;
  if (!message) throw new Error("no choices in reply");
  if (message.refusal) throw new LifoRefusal(message.refusal);

  const tokens = reply.usage?.total_tokens ?? 0;

  // Tool calls before content. A completion carrying both wants the tool run
  // before it commits to prose, and answering with the prose strands it.
  if (message.tool_calls && message.tool_calls.length > 0) {
    return {
      kind: "tool_calls" as const,
      toolCalls: message.tool_calls.map((call) => ({
        id: call.id,
        name: call.function.name,
        arguments: call.function.arguments,
      })),
      tokens,
    };
  }
  if (!message.content) throw new Error("empty content");
  return { kind: "text" as const, text: message.content, tokens };
}

// The door's whole validation, hoisted here so it is tested rather than
// living inside Deno.serve where it is not.
export function parseRequest(body: unknown) {
  if (typeof body !== "object" || body === null) return null;
  const raw = body as Record<string, unknown>;
  const task = String(raw.task ?? "");
  if (!taskConfig(task)) return null;

  if (task === "chat") {
    const messages = Array.isArray(raw.messages) ? raw.messages : [];
    const tools = Array.isArray(raw.tools) ? raw.tools : [];
    if (messages.length === 0) return null;
    // A string or nothing. Anything else is a client that does not know the
    // shape, and coercing it with String() would put "[object Object]" into
    // a system message.
    const context = typeof raw.context === "string" ? raw.context : "";
    return { kind: "chat" as const, messages, tools, context };
  }

  const prompt = String(raw.prompt ?? "");
  if (!prompt) return null;
  return { kind: "prompt" as const, task, prompt };
}
