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

export function parseOutput(
  task: string,
  body: unknown,
): { output: Record<string, unknown>; tokens: number } {
  const reply = body as {
    choices?: { message?: { content?: string; refusal?: string } }[];
    usage?: { total_tokens?: number };
  };
  const message = reply.choices?.[0]?.message;
  if (!message) throw new Error("no choices in reply");
  if (message.refusal) throw new LifoRefusal(message.refusal);
  if (!message.content) throw new Error("empty content");
  const output = JSON.parse(message.content) as Record<string, unknown>;
  if (taskConfig(task) && typeof output.answer !== "string") {
    throw new Error("output missing answer");
  }
  return { output, tokens: reply.usage?.total_tokens ?? 0 };
}
