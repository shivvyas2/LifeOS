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

// `schema` is optional because the chat task genuinely has none. A chat
// completion may come back as prose or as tool calls, so there is no single
// output shape to validate it against, and `parseChatReply` does not try.
// Pointing chat at the answer task's schema, as this used to, made the entry
// read as though chat replies were validated when nothing ever looked at it.
const TASKS: Record<string, { model: string; system: string; schema?: Record<string, unknown> }> = {
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

// A verbatim copy of ResponseStyle.conversation in LifeOSKit. The two tiers
// are meant to write identically, and this copy had already drifted at birth:
// it dropped the quotation mark prohibition and the "if you can answer
// without asking, answer" clause, so the cloud model was allowed two habits
// the device model was not. Keep them identical; a Deno test and a Swift test
// each pin the same prohibitions and permissions.
const CONVERSATION = `Write in plain sentences, the way a person speaks.

Never use markdown. No asterisks, no underscores, no backticks, no hash headings, no bullet characters, no numbered lists. If you need to list things, write them as a sentence separated by commas, or as separate short sentences.

Never use em dashes or en dashes. Use a comma, or start a new sentence.

Never wrap words in quotation marks for emphasis. Apostrophes in contractions are fine.

Give figures as figures with their units. Never invent one, and never round a number you were given into a different number.

You are in a conversation, not filling in a form. You may refer back to what was said earlier in this thread, and you may acknowledge what the person told you before you answer.

When you genuinely need something in order to answer well, ask one question back. One, not a list, and not out of habit. If you can answer without asking, answer.`;

// The chat task. SCOPE first and always: the guardrail is the reason this
// prompt lives on the server, and the conversational permissions are added
// behind it rather than in place of it.
TASKS.chat = {
  model: "gpt-5-mini",
  system: `${SCOPE}\n\n${CONVERSATION}`,
};

// The nudge task: one sentence for a lock screen, from numbers a rule already
// worked out.
//
// SCOPE and CONVERSATION first, exactly as chat has them. A notification is
// still LIFO speaking about this person's own data, so it inherits the same
// guardrail and the same typography prohibitions; a markdown asterisk reads
// no better on a lock screen than it does in a bubble.
//
// The model's whole job here is phrasing. It is not given the rows, only the
// figures the fired trigger carried, which is what keeps this call on the
// order of 300 tokens in and 60 out.
TASKS.nudge = {
  model: "gpt-5-mini",
  system: `${SCOPE}

${CONVERSATION}

You are writing a single notification. At most two sentences, under 180
characters. Do not greet them and do not sign off. Use only the figures you
are given; if a figure is not there, do not mention it.`,
  schema: {
    name: "lifo_nudge",
    strict: true,
    schema: {
      type: "object",
      properties: { text: { type: "string" } },
      required: ["text"],
      additionalProperties: false,
    },
  },
};

/// The nudge's own daily allowance, separate from DAILY_TOKEN_CAP.
///
/// The phrasing call is tiny, so this is not really a spend limit: it is a
/// runaway guard. The reason it is a separate budget at all is that a heavy
/// chat evening must not be able to eat the next morning's nudge.
export const NUDGE_TOKEN_CAP = 4_000;

export function taskConfig(task: string) {
  return TASKS[task] ?? null;
}

export function openAIBody(task: string, prompt: string): Record<string, unknown> {
  const config = taskConfig(task);
  if (!config) throw new Error(`unknown task: ${task}`);
  // A one-shot task without a schema would be asked for typed JSON and given
  // no shape to produce, which is a programming error rather than a request
  // this could serve. The chat task never comes through here.
  if (!config.schema) throw new Error(`task has no schema: ${task}`);
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
  if (!config.schema) throw new Error(`task has no schema: ${task}`);

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

// What a client is allowed to put in the thread. Notably not "system": a
// system message from the client lands AFTER the server's own, and providers
// weight the later one heavily, so accepting one is accepting that SCOPE can
// be talked around by anybody who can edit a request body. The context field
// exists so a client never needs to write a system message at all.
const ALLOWED_CHAT_ROLES = new Set(["user", "assistant", "tool"]);

// Bounds, not tuning knobs. Without them this endpoint is a general OpenAI
// proxy on our key for any authenticated user: an unbounded thread, an
// unbounded tool list, and an unbounded context are three ways to spend the
// whole daily allowance in one request on something that is not coaching.
// The device sends at most a 20 turn window plus its tool round trips, six
// calendar tools, and a context the render budgets at 8000 characters.
export const MAX_CHAT_MESSAGES = 64;
export const MAX_CHAT_TOOLS = 16;
export const MAX_CONTEXT_LENGTH = 32_000;

function isAllowedChatMessage(message: unknown): boolean {
  if (typeof message !== "object" || message === null || Array.isArray(message)) {
    return false;
  }
  const raw = message as Record<string, unknown>;
  if (typeof raw.role !== "string" || !ALLOWED_CHAT_ROLES.has(raw.role)) return false;
  // Content is a string on every message the device sends, including the
  // empty one that carries tool calls. Anything else is a shape we would be
  // forwarding to the provider without having read it.
  if (typeof raw.content !== "string") return false;
  return true;
}

function isFunctionTool(tool: unknown): boolean {
  if (typeof tool !== "object" || tool === null || Array.isArray(tool)) return false;
  const raw = tool as Record<string, unknown>;
  if (raw.type !== "function") return false;
  const fn = raw.function;
  if (typeof fn !== "object" || fn === null) return false;
  return typeof (fn as Record<string, unknown>).name === "string";
}

// The door's whole validation, hoisted here so it is tested rather than
// living inside Deno.serve where it is not.
export function parseRequest(body: unknown) {
  if (typeof body !== "object" || body === null) return null;
  const raw = body as Record<string, unknown>;
  const task = String(raw.task ?? "");
  if (!taskConfig(task)) return null;

  if (task === "chat") {
    if (!Array.isArray(raw.messages) || raw.messages.length === 0) return null;
    if (raw.messages.length > MAX_CHAT_MESSAGES) return null;
    if (!raw.messages.every(isAllowedChatMessage)) return null;

    const tools = Array.isArray(raw.tools) ? raw.tools : [];
    if (tools.length > MAX_CHAT_TOOLS) return null;
    if (!tools.every(isFunctionTool)) return null;

    // A string or nothing. Anything else is a client that does not know the
    // shape, and coercing it with String() would put "[object Object]" into
    // a system message.
    const context = typeof raw.context === "string" ? raw.context : "";
    if (context.length > MAX_CONTEXT_LENGTH) return null;

    return { kind: "chat" as const, messages: raw.messages, tools, context };
  }

  const prompt = String(raw.prompt ?? "");
  if (!prompt) return null;
  return { kind: "prompt" as const, task, prompt };
}
