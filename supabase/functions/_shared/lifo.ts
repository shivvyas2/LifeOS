// The server side of LIFO's brain: model choice, guardrails, schema, and
// reply parsing. Pure functions only, so every decision here is testable
// without a network. index.ts owns the door (auth, budget, the call).

import type Anthropic from "npm:@anthropic-ai/sdk@0.131.0";

/// One model for every task. Claude Opus 5.5 thinks on every request; effort
/// is the only dial on how much, and therefore on latency and spend.
export const MODEL = "claude-opus-5-5";

/// The daily chat allowance, in billed tokens (see `billedTokens`), not raw
/// tokens.
///
/// Sized from the cost ceiling rather than from a usage guess: LifeOS ships
/// free and has to stay under about $2 per user per month. A user who spends
/// this every day for 30 days costs about $1.92 at Opus 5.5's $4 per million
/// input tokens. The old figure, 150,000 raw tokens, was the same ceiling
/// worked out at gpt-5-mini's prices.
export const DAILY_TOKEN_CAP = 16_000;

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
// reply may come back as prose or as tool calls, so there is no single
// output shape to validate it against, and `parseChatReply` does not try.
// Pointing chat at the answer task's schema, as this used to, made the entry
// read as though chat replies were validated when nothing ever looked at it.
//
// `maxTokens` covers the thinking as well as the reply, because thinking
// counts toward the limit even though its text is never returned. The limits
// are tight on purpose: at $20 per million output tokens one runaway reply
// at a generous limit would spend several days of the allowance at once.
const TASKS: Record<
  string,
  { system: string; maxTokens: number; schema?: Record<string, unknown> }
> = {
  answer: {
    system: `${SCOPE}

Answer the user's question in one short, direct paragraph. No preamble,
no restating the question.`,
    maxTokens: 8_000,
    schema: {
      type: "object",
      properties: { answer: { type: "string" } },
      required: ["answer"],
      additionalProperties: false,
    },
  },
  plan: {
    system: `You plan software projects for one developer. From the project's
name, scope, dates, milestones, README and recent commit subjects, list the
features to build, in the order to build them. Each feature is something a
person can see working when it is done, small enough for one branch and one
pull request. Give 3 to 12. For each: a title of at most 8 words, a one
sentence note, a branch name of the form feat/<words-with-dashes>, and the
title of the milestone it belongs to from the given list, or an empty string.
Do not repeat work the commits show is already done. If the owner adds a
nudge, follow it.`,
    maxTokens: 6_000,
    schema: {
      type: "object",
      properties: {
        features: {
          type: "array",
          items: {
            type: "object",
            properties: {
              title: { type: "string" },
              note: { type: "string" },
              branch: { type: "string" },
              milestone: { type: "string" },
            },
            required: ["title", "note", "branch", "milestone"],
            additionalProperties: false,
          },
        },
      },
      required: ["features"],
      additionalProperties: false,
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
  system: `${SCOPE}\n\n${CONVERSATION}`,
  maxTokens: 8_000,
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
// figures the fired trigger carried, which keeps the reply to a sentence and
// the thinking at low effort short.
TASKS.nudge = {
  system: `${SCOPE}

${CONVERSATION}

You are writing a single notification. At most two sentences, under 180
characters. Do not greet them and do not sign off. Use only the figures you
are given; if a figure is not there, do not mention it.`,
  maxTokens: 2_000,
  schema: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  },
};

/// The nudge's own daily allowance, separate from DAILY_TOKEN_CAP, and in
/// the same billed units.
///
/// The phrasing call is tiny, so this is not really a spend limit: it is a
/// runaway guard. The reason it is a separate budget at all is that a heavy
/// chat evening must not be able to eat the next morning's nudge.
export const NUDGE_TOKEN_CAP = 4_000;

/// Ten drafts a day at the task's ceiling, kept apart from chat so planning
/// a project never eats the evening's coaching.
export const PLAN_TOKEN_CAP = 60_000;
export const MAX_PLAN_PROMPT = 12_000;

type Parsed = NonNullable<ReturnType<typeof parseRequest>>;

export function usageKind(parsed: Parsed | { kind: "prompt"; task: string; prompt: string }): "chat" | "plan" {
  return parsed.kind === "prompt" && parsed.task === "plan" ? "plan" : "chat";
}

export function usageCap(kind: "chat" | "plan"): number {
  return kind === "plan" ? PLAN_TOKEN_CAP : DAILY_TOKEN_CAP;
}

/// Cuts a plan to what the features table accepts (title 80, note 280,
/// branch 255, counted in code points like char_length) and to twelve.
export function cleanPlan(output: Record<string, unknown>) {
  if (!Array.isArray(output.features)) throw new Error("plan without features");
  const cut = (value: unknown, max: number) => [...String(value ?? "").trim()].slice(0, max).join("");
  const features = output.features
    .map((raw) => {
      const item = (raw ?? {}) as Record<string, unknown>;
      return {
        title: cut(item.title, 80),
        note: cut(item.note, 280),
        branch: cut(item.branch, 255),
        milestone: cut(item.milestone, 80),
      };
    })
    .filter((item) => item.title.length > 0)
    .slice(0, 12);
  if (features.length === 0) throw new Error("empty plan");
  return { features };
}

export function taskConfig(task: string) {
  return TASKS[task] ?? null;
}

/// The one setting that is worth having and is not worth an outage.
///
/// Opus 5.5 defaults to medium effort, and medium is most of the wait. A
/// coaching question over a week of the user's own numbers is not a
/// reasoning problem; the thinking that matters already happened on the
/// device when the digest was built. Low also spends fewer tokens, which is
/// the same lever as the daily cap pulled from the other end.
const EFFORT = "low" as const;

export function taskBody(task: string, prompt: string): Anthropic.MessageCreateParamsNonStreaming {
  const config = taskConfig(task);
  if (!config) throw new Error(`unknown task: ${task}`);
  // A one-shot task without a schema would be asked for typed JSON and given
  // no shape to produce, which is a programming error rather than a request
  // this could serve. The chat task never comes through here.
  if (!config.schema) throw new Error(`task has no schema: ${task}`);
  return {
    model: MODEL,
    max_tokens: config.maxTokens,
    system: config.system,
    messages: [{ role: "user", content: prompt }],
    output_config: {
      effort: EFFORT,
      format: { type: "json_schema", schema: config.schema },
    },
  };
}

/// The same body with the effort removed, for the one retry after a 400.
///
/// A model that stops accepting the setting must cost a slower answer, never
/// no answer at all. Only the effort goes: the output format is the task's
/// contract and the retry still needs it.
export function withoutTuning<T extends Anthropic.MessageCreateParams>(body: T): T {
  if (!body.output_config) return body;
  const { effort: _effort, ...rest } = body.output_config;
  return { ...body, output_config: rest };
}

export function classifyFailure(status: number | undefined): "rate_limited" | "upstream_failure" {
  return status === 429 ? "rate_limited" : "upstream_failure";
}

/// What a request cost, in the units the daily caps are written in: tokens
/// at the base input price.
///
/// Raw token counts misprice this model in both directions. A cache read
/// costs a twentieth of a fresh input token and an output token five times
/// one, so a cap on raw tokens would punish a long conversation that is
/// mostly cached and undercharge a short one that writes a lot. Weighting by
/// price keeps the cap a cap on money, which is what it is for.
export function billedTokens(usage: {
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
  cache_read_input_tokens?: number | null;
}): number {
  const weighted = (usage.input_tokens ?? 0) +
    (usage.cache_creation_input_tokens ?? 0) * 1.25 +
    (usage.cache_read_input_tokens ?? 0) * 0.05 +
    (usage.output_tokens ?? 0) * 5;
  return Math.ceil(weighted);
}

/// The reason to hand the user when the model declines.
///
/// A refusal arrives as a successful reply with stop_reason "refusal", not
/// as an error, and its explanation is optional, so it is read rather than
/// assumed.
function refusalReason(message: Anthropic.Message): string {
  return message.stop_details?.explanation ?? "That is not something I can help with.";
}

function replyText(message: Anthropic.Message): string {
  // By block type, never by position: a reply opens with thinking blocks,
  // whose text is empty because it is never returned.
  return message.content
    .filter((block): block is Anthropic.TextBlock => block.type === "text")
    .map((block) => block.text)
    .join("");
}

// Validates the parsed reply against the task's own schema, rather than a
// literal field name, so a later task with a different output shape is
// checked against its real schema instead of being rubber-stamped by one
// written for "answer". Only handles the property types this project's
// schemas actually declare (string); anything else throws loudly, so a
// future schema addition can't silently skip validation.
function validateShape(schema: Record<string, unknown>, output: Record<string, unknown>): void {
  const inner = schema as {
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
    } else if (declaredType === "array") {
      if (!Array.isArray(value)) throw new Error(`output missing required property "${key}"`);
    } else {
      throw new Error(`unsupported schema type "${declaredType}" for property "${key}"`);
    }
  }
}

export function parseOutput(
  task: string,
  message: Anthropic.Message,
): { output: Record<string, unknown>; tokens: number } {
  const config = taskConfig(task);
  if (!config) throw new Error(`unknown task: ${task}`);
  if (!config.schema) throw new Error(`task has no schema: ${task}`);

  if (message.stop_reason === "refusal") throw new LifoRefusal(refusalReason(message));
  const text = replyText(message);
  if (!text) throw new Error("empty content");
  const output = JSON.parse(text) as Record<string, unknown>;
  validateShape(config.schema, output);
  return { output, tokens: billedTokens(message.usage) };
}

// The device's own wire format for a thread. It is OpenAI's chat message
// shape with tool_calls kept flat, because that is what the phone shipped
// with, and the phone never learns the provider's message schema: that is
// what lets the provider change without an app release. Everything below
// translates it, right before the request leaves.
interface WireMessage {
  role: "user" | "assistant" | "tool";
  content: string;
  tool_calls?: { id: string; name: string; arguments: string }[];
  tool_call_id?: string;
}

function toolInput(argumentsJSON: string): Record<string, unknown> {
  // These are arguments the model itself produced and the phone echoed back,
  // so they parse in practice. If one does not, an empty input still keeps
  // the call paired with its result, which the provider requires.
  try {
    const parsed = JSON.parse(argumentsJSON);
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

/// The device's thread, in Claude's message shape.
///
/// A tool result is a block in a user turn rather than a role of its own,
/// and every result answering one assistant turn has to arrive in the same
/// user turn, so consecutive turns of one role are merged. Empty text is
/// dropped because the provider rejects an empty text block, and the device
/// sends one on every assistant turn that only carries tool calls.
export function toClaudeMessages(messages: unknown[]): Anthropic.MessageParam[] {
  const thread: { role: "user" | "assistant"; content: Anthropic.ContentBlockParam[] }[] = [];
  for (const message of messages as WireMessage[]) {
    let role: "user" | "assistant";
    const blocks: Anthropic.ContentBlockParam[] = [];
    if (message.role === "tool") {
      role = "user";
      blocks.push({
        type: "tool_result",
        tool_use_id: message.tool_call_id ?? "",
        content: message.content,
      });
    } else {
      role = message.role;
      if (message.content) blocks.push({ type: "text", text: message.content });
      for (const call of message.tool_calls ?? []) {
        blocks.push({ type: "tool_use", id: call.id, name: call.name, input: toolInput(call.arguments) });
      }
    }
    if (blocks.length === 0) continue;
    const previous = thread[thread.length - 1];
    if (previous && previous.role === role) previous.content.push(...blocks);
    else thread.push({ role, content: blocks });
  }
  // The device sends a sliding window, and a window can open part way
  // through an exchange: on an assistant turn, or on tool results whose call
  // fell off the front. Neither is a valid first turn, so the thread starts
  // at the first thing the person actually said.
  while (
    thread.length > 0 &&
    (thread[0].role !== "user" || thread[0].content[0].type === "tool_result")
  ) {
    thread.shift();
  }
  return thread;
}

/// A device tool declaration ({type: "function", function: {...}}) as a
/// Claude tool. Validated already by `parseRequest`.
function toClaudeTool(tool: unknown): Anthropic.Tool {
  const fn = (tool as { function: { name: string; description?: string; parameters?: unknown } })
    .function;
  return {
    name: fn.name,
    ...(fn.description ? { description: fn.description } : {}),
    input_schema: (fn.parameters ?? { type: "object", properties: {} }) as Anthropic.Tool.InputSchema,
  };
}

// `context` is the device's rendered view of the user's own data, or the
// calendar assistant's rules and the current date. It arrives in a field of
// its own, never as a message, and it is placed here: a system block behind
// SCOPE. Order is the point. SCOPE stays first so the guardrail is never
// displaced by anything the client sent, and the context sits behind it
// because the model is told to cite only numbers it was given, which
// requires actually giving it some.
export function chatBody(
  messages: unknown[],
  tools: unknown[],
  context = "",
): Anthropic.MessageCreateParamsNonStreaming {
  const structuredCoach = context.includes("LIFEOS_STRUCTURED_COACH_V1") && tools.length === 0;
  const coachStyle = `${SCOPE}

Answer directly in one or two sentences. Usually stay under 120 words unless asked for detail.
Use brief Markdown tables for supplied metrics or comparisons, and at most three bullets for actions.
Use at most three sections. No greeting, filler, repeated conclusion, or invented numbers.
Keep units and time periods. Say when data is missing. Follow the requested presentation format.
When the presentation format asks for a SAY: line, write it first, on its own line, before anything else.`;
  const system: Anthropic.TextBlockParam[] = [
    { type: "text", text: structuredCoach ? coachStyle : TASKS.chat.system },
  ];
  if (context) system.push({ type: "text", text: context });
  // A cache breakpoint at the end of the system prompt. The thread is a
  // sliding window, so once it starts sliding the messages stop matching the
  // previous request; this breakpoint keeps the tools, guardrail and context
  // cached through that, and the top-level one below caches the thread while
  // it is still growing.
  system[system.length - 1].cache_control = { type: "ephemeral" };

  const body: Anthropic.MessageCreateParamsNonStreaming = {
    model: MODEL,
    max_tokens: TASKS.chat.maxTokens,
    system,
    messages: toClaudeMessages(messages),
    cache_control: { type: "ephemeral" },
    output_config: { effort: EFFORT },
  };
  // Absent rather than empty: a thread with no tools has nothing to declare.
  if (tools.length > 0) {
    body.tools = tools.map(toClaudeTool);
    body.tool_choice = { type: "auto" };
  }
  return body;
}

/// One event of the provider's stream, reduced to what we act on.
///
/// Pure, so the reassembly is testable without a network, the same division
/// the rest of this file keeps. Usage arrives in two halves: the input side
/// in `message_start`, and running totals in each `message_delta`.
export function parseStreamEvent(event: Anthropic.RawMessageStreamEvent): {
  delta?: string;
  stopReason?: string;
  refusal?: string;
  usage?: Parameters<typeof billedTokens>[0];
} {
  switch (event.type) {
    case "message_start":
      return { usage: event.message.usage };
    case "content_block_delta":
      // Only text reaches the person. Thinking deltas carry nothing under
      // the default display, and tool input never streams because a turn
      // with tools is never streamed.
      if (event.delta.type === "text_delta" && event.delta.text.length > 0) {
        return { delta: event.delta.text };
      }
      return {};
    case "message_delta": {
      const out: ReturnType<typeof parseStreamEvent> = { usage: event.usage };
      if (event.delta.stop_reason) out.stopReason = event.delta.stop_reason;
      if (event.delta.stop_reason === "refusal") {
        out.refusal = event.delta.stop_details?.explanation ??
          "That is not something I can help with.";
      }
      return out;
    }
    default:
      return {};
  }
}

/// Folds a later usage report over an earlier one. A field the later report
/// leaves null keeps its earlier value, because `message_delta` only
/// restates what it knows.
export function mergeUsage(
  earlier: Parameters<typeof billedTokens>[0],
  later: Parameters<typeof billedTokens>[0],
): Parameters<typeof billedTokens>[0] {
  const merged = { ...earlier };
  for (const [key, value] of Object.entries(later)) {
    if (typeof value === "number") (merged as Record<string, number>)[key] = value;
  }
  return merged;
}

export function parseChatReply(message: Anthropic.Message) {
  if (message.stop_reason === "refusal") throw new LifoRefusal(refusalReason(message));

  const tokens = billedTokens(message.usage);

  // Tool calls before text. A reply carrying both wants the tool run before
  // it commits to prose, and answering with the prose strands it.
  const calls = message.content.filter(
    (block): block is Anthropic.ToolUseBlock => block.type === "tool_use",
  );
  if (calls.length > 0) {
    return {
      kind: "tool_calls" as const,
      toolCalls: calls.map((call) => ({
        id: call.id,
        name: call.name,
        arguments: JSON.stringify(call.input),
      })),
      tokens,
    };
  }
  const text = replyText(message);
  if (!text) throw new Error("empty content");
  return { kind: "text" as const, text, tokens };
}

// What a client is allowed to put in the thread. Notably not "system": a
// system message from the client lands AFTER the server's own, and providers
// weight the later one heavily, so accepting one is accepting that SCOPE can
// be talked around by anybody who can edit a request body. The context field
// exists so a client never needs to write a system message at all.
const ALLOWED_CHAT_ROLES = new Set(["user", "assistant", "tool"]);

// Bounds, not tuning knobs. Without them this endpoint is a general model
// proxy on our key for any authenticated user: an unbounded thread, an
// unbounded tool list, and an unbounded context are three ways to spend the
// whole daily allowance in one request on something that is not coaching.
// The device sends at most a 20 turn window plus its tool round trips, six
// calendar tools, and a context the render budgets at 8000 characters.
export const MAX_CHAT_MESSAGES = 64;
export const MAX_CHAT_TOOLS = 16;
export const MAX_CONTEXT_LENGTH = 32_000;

function isWireToolCall(call: unknown): boolean {
  if (typeof call !== "object" || call === null) return false;
  const raw = call as Record<string, unknown>;
  return typeof raw.id === "string" && typeof raw.name === "string" &&
    typeof raw.arguments === "string";
}

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
  // The tool fields are read now, to translate them, so they are checked
  // like everything else that is read: a result must name the call it
  // answers, and a call must carry the three strings the device writes.
  if (raw.role === "tool" && typeof raw.tool_call_id !== "string") return false;
  if (raw.tool_calls !== undefined) {
    if (raw.role !== "assistant" || !Array.isArray(raw.tool_calls)) return false;
    if (!raw.tool_calls.every(isWireToolCall)) return false;
  }
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

    // Streaming is the client asking to be handed text as it arrives, and it
    // is only ever honoured for a turn with no tools. A tool call arrives in
    // a stream as fragments of a JSON argument string spread across events,
    // and reassembling those on the server would put half the device's round
    // loop up here. The coach passes no tools and is the screen someone
    // watches; the calendar assistant passes tools and is not.
    const stream = raw.stream === true && tools.length === 0;

    return { kind: "chat" as const, messages: raw.messages, tools, context, stream };
  }

  const prompt = String(raw.prompt ?? "");
  if (!prompt) return null;
  if (task === "plan" && prompt.length > MAX_PLAN_PROMPT) return null;
  return { kind: "prompt" as const, task, prompt };
}
