# LIFO Agent Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the `CoachRouter` remote slot with an OpenAI-backed engine behind a `lifo-agent` Edge Function, feeding it a device-assembled context bundle, with a server-enforced daily token budget.

**Architecture:** The device builds a `ContextBundle` (metrics digest + money + sectors), renders it for the `.offDevice` audience, and posts `{task, prompt}` to a JWT-gated Edge Function. The function holds the OpenAI key and the system guardrails, checks a per-user daily token ledger, calls `gpt-5-mini`, debits the ledger, and returns JSON the app decodes into the task's output type. The router's existing result vocabulary maps every failure onto UI that already exists.

**Tech Stack:** Swift (LifeOSKit `Insights` module, SwiftPM tests), Deno/TypeScript Edge Functions (`jsr:@std/assert@1` tests), Supabase (Postgres migration, function secrets), OpenAI Chat Completions with `response_format: json_schema`.

**Spec:** `docs/superpowers/specs/2026-08-26-lifo-agent-design.md`

## Global Constraints

- Never commit to main; branch per change, conventional commits, no em dashes in messages, no Co-Authored-By trailer.
- Work in a git worktree (peer sessions share the main checkout).
- The OpenAI key exists only as the `OPENAI_API_KEY` function secret; never in the app, never in the repo.
- The context bundle is never stored or logged server-side; log lines carry ids, task names, token counts, latency only.
- Raw Whoop series never leave the phone: every remote render goes through the `.offDevice` audience.
- Daily cap: 150,000 tokens/user/day, enforced server-side (spec's $2/user/month ceiling).
- Server prompt pins scope: coaching this user over their own LifeOS data; no diagnoses, no investment picks.
- iOS 26 / Swift 6 targets; match surrounding code style (comment density, `///` doc style).

---

### Task 1: Thread an audience through CoachTask.prompt

The blocker named in `Engine.swift`: a remote engine must never receive the on-device render. Give `prompt` an audience parameter and route both tasks through `promptLines(for:)`.

**Files:**
- Modify: `LifeOSKit/Sources/Insights/CoachTask.swift`
- Modify: `LifeOSKit/Sources/Insights/Engines/OnDeviceEngine.swift` (the `task.prompt(context)` call site)
- Modify: `LifeOSKit/Sources/Insights/Engines/Engine.swift` (delete the now-stale warning comment paragraph about the missing audience parameter; keep the protocol unchanged)
- Test: `LifeOSKit/Tests/InsightsTests/CoachTaskTests.swift`

**Interfaces:**
- Consumes: `MetricsDigest.Audience` (`.onDevice` / `.offDevice`), `digest.promptLines(for:budget:)`.
- Produces: `func prompt(_ context: Context, for audience: MetricsDigest.Audience) -> String` as the CoachTask requirement. Task 6 and Task 7 call this.

- [ ] **Step 1: Write the failing test**

Append to `CoachTaskTests.swift` (match its existing `@Suite`/`@Test` or `XCTest` style — read the file first and use the same framework):

```swift
@Test func theOffDeviceRenderCarriesNoRawSeries() {
    let digest = MetricsDigest.fixture()   // reuse the fixture MetricsDigestTests uses
    let task = AnswerTask(question: "How did I sleep?")
    let local = task.prompt(digest, for: .onDevice)
    let remote = task.prompt(digest, for: .offDevice)
    #expect(local != remote)
    // The on-device baseline includes HRV; the off-device render must not.
    #expect(!remote.contains("hrv"))
}
```

If `MetricsDigest.fixture()` does not exist, build the digest the way `MetricsDigestTests.swift` builds one (copy its arrange block) rather than inventing a new helper.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LifeOSKit && swift test --filter CoachTaskTests`
Expected: FAIL to compile with "missing argument for parameter 'for'" (the new signature does not exist yet).

- [ ] **Step 3: Change the protocol and both tasks**

In `CoachTask.swift`, replace the `prompt` requirement and its stale doc comment:

```swift
    /// Renders the context for a given audience. `.onDevice` may carry raw
    /// series; `.offDevice` must never, which is why the audience is a
    /// parameter here rather than a policy inside each engine.
    func prompt(_ context: Context, for audience: MetricsDigest.Audience) -> String
```

Update both conformances:

```swift
// BriefTask
public func prompt(_ digest: MetricsDigest, for audience: MetricsDigest.Audience) -> String {
    """
    Here are the most recent days:

    \(digest.promptLines(for: audience))

    Write today's brief.
    """
}

// AnswerTask
public func prompt(_ digest: MetricsDigest, for audience: MetricsDigest.Audience) -> String {
    """
    Here are the most recent days:

    \(digest.promptLines(for: audience))

    Question: \(question)
    """
}
```

In `OnDeviceEngine.swift`, change the call site from `task.prompt(context)` to `task.prompt(context, for: .onDevice)`.

Update the `Audience` doc comment in `MetricsDigest.swift` (lines ~75-82): the mechanism is now wired; trim the "waiting to be wired" paragraph to match reality.

- [ ] **Step 4: Run the full kit suite**

Run: `cd LifeOSKit && swift test`
Expected: PASS (all 552+; the audience change compiles everywhere).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit
git commit -m "feat(coach): thread the render audience through CoachTask.prompt"
```

---

### Task 2: The lifo_usage ledger migration

**Files:**
- Create: `supabase/migrations/20260827090000_lifo_usage.sql`

**Interfaces:**
- Produces: table `public.lifo_usage(user_id, day, tokens)` and SQL function `public.lifo_debit(p_user uuid, p_tokens bigint) returns bigint`. Task 4 calls `lifo_debit` and reads `lifo_usage` via the service client.

- [ ] **Step 1: Write the migration**

```sql
-- One row per user per day: how many tokens LIFO has spent for them.
-- The ledger is the budget guardrail; the cap itself lives in the Edge
-- Function so changing it is a deploy, not a migration.
create table public.lifo_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null default current_date,
  tokens bigint not null default 0,
  primary key (user_id, day)
);

-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner: usage is bookkeeping between the Edge Function
-- and the model provider, and the service role is the only reader.
alter table public.lifo_usage enable row level security;

-- Upsert-and-add in one statement, so two concurrent turns cannot both read
-- the same starting balance and each write their own. Returns the new total
-- so the caller can log it without a second round trip.
create function public.lifo_debit(p_user uuid, p_tokens bigint)
returns bigint
language sql
security definer
set search_path = public
as $$
  insert into lifo_usage (user_id, day, tokens)
  values (p_user, current_date, p_tokens)
  on conflict (user_id, day)
  do update set tokens = lifo_usage.tokens + excluded.tokens
  returning tokens;
$$;

-- Only the service role may spend; definer or not, keep the front door shut.
revoke execute on function public.lifo_debit from public, anon, authenticated;
```

- [ ] **Step 2: Verify it applies cleanly**

Run: `supabase db push --dry-run`
Expected: lists exactly `20260827090000_lifo_usage.sql` as pending, no errors. (The real push happens in Task 8 with the deploy.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260827090000_lifo_usage.sql
git commit -m "feat(lifo): daily token ledger table and atomic debit"
```

---

### Task 3: Shared lifo.ts helpers, test-first

All the decidable server logic lives in `_shared/lifo.ts` so `index.ts` stays a thin door, matching how `plaid.ts` carries `plaid-sync`'s brains.

**Files:**
- Create: `supabase/functions/_shared/lifo.ts`
- Test: `supabase/functions/_shared/lifo_test.ts`

**Interfaces:**
- Consumes: nothing app-side; pure functions.
- Produces (Task 4 imports all of these):
  - `DAILY_TOKEN_CAP: number` (150_000)
  - `taskConfig(task: string): { model: string; system: string; schema: Record<string, unknown> } | null`
  - `openAIBody(task: string, prompt: string): Record<string, unknown>` (throws on unknown task)
  - `classifyOpenAIFailure(status: number): "rate_limited" | "upstream_failure"`
  - `parseOutput(task: string, body: unknown): { output: Record<string, unknown>; tokens: number }` (throws `LifoRefusal` with a message on a model refusal, `Error` on malformed bodies)
  - `class LifoRefusal extends Error`

- [ ] **Step 1: Write the failing tests**

`supabase/functions/_shared/lifo_test.ts`:

```typescript
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/_shared/lifo_test.ts`
Expected: FAIL, module `./lifo.ts` not found.

- [ ] **Step 3: Implement lifo.ts**

```typescript
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/_shared/lifo_test.ts`
Expected: PASS, all 9.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/lifo.ts supabase/functions/_shared/lifo_test.ts
git commit -m "feat(lifo): server-side task config, guardrails, and reply parsing"
```

---

### Task 4: The lifo-agent Edge Function

**Files:**
- Create: `supabase/functions/lifo-agent/index.ts`

**Interfaces:**
- Consumes: `resolveUser`, `serviceClient`, `json` from `../_shared/plaid.ts` (they are generic auth/response helpers despite the filename); everything from `../_shared/lifo.ts`; table/function from Task 2.
- Produces: `POST /functions/v1/lifo-agent` accepting `{ task: string, prompt: string }` with the user's JWT in `Authorization`. Replies: `200 {output, tokens}`, `400 {error:"invalid_body"|"unknown_task"}`, `401 {error:"unauthorized"}`, `403 {error:"refused", message}`, `405`, `429 {error:"exhausted"}`, `500 {error:"server_not_configured"|"storage_failed"}`, `502 {error:"rate_limited"|"upstream_failure"}`. Task 7's wire decodes exactly these.

- [ ] **Step 1: Write index.ts**

```typescript
import { json, resolveUser, serviceClient } from "../_shared/plaid.ts";
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
```

- [ ] **Step 2: Type-check it**

Run: `deno check supabase/functions/lifo-agent/index.ts`
Expected: no errors. (The endpoint's brains were tested in Task 3; the door itself is exercised end-to-end in Task 8.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/lifo-agent/index.ts
git commit -m "feat(lifo): JWT-gated agent endpoint with budget ledger"
```

---

### Task 5: ContextBundle

**Files:**
- Create: `LifeOSKit/Sources/Insights/Context/ContextBundle.swift`
- Test: `LifeOSKit/Tests/InsightsTests/ContextBundleTests.swift`

**Interfaces:**
- Consumes: `MetricsDigest` and its `Audience`.
- Produces (Task 6 consumes): `ContextBundle` with `init(digest:money:sectors:firstName:)`, nested `Money` (`income`, `expenses`, `savingsRate: Double?`, `netWorth: Double?`, `recent: [Money.Transaction]` where `Transaction` is `merchant: String, category: String?, amount: Double, date: Date`), nested `Sector` (`name: String, score: Int?, delta: Int?`), and `func promptLines(for audience: MetricsDigest.Audience, budget: Int = 8_000) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Insights

struct ContextBundleTests {
    private func bundle(transactions: Int = 3) -> ContextBundle {
        let recent = (0..<transactions).map {
            ContextBundle.Money.Transaction(
                merchant: "Merchant \($0)", category: "Food",
                amount: -12.5, date: Date(timeIntervalSince1970: 1_756_000_000)
            )
        }
        return ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(
                income: 8000, expenses: 5000, savingsRate: 0.37,
                netWorth: 25_000, recent: recent
            ),
            sectors: [
                ContextBundle.Sector(name: "Body", score: 7, delta: 1),
                ContextBundle.Sector(name: "Money", score: nil, delta: nil),
            ],
            firstName: "Shiv"
        )
    }

    @Test func theOffDeviceRenderCarriesEverySection() {
        let lines = bundle().promptLines(for: .offDevice)
        #expect(lines.contains("Merchant 0"))
        #expect(lines.contains("Body 7 (+1)"))
        #expect(lines.contains("Money unscored"))
        #expect(lines.contains("Shiv"))
    }

    // The on-device window is small; transactions would drown the digest.
    @Test func theOnDeviceRenderSkipsTransactionDetail() {
        let lines = bundle().promptLines(for: .onDevice)
        #expect(!lines.contains("Merchant 0"))
        #expect(lines.contains("Body 7 (+1)"))
    }

    // Truncation drops transaction detail first; sectors and the money
    // summary survive because they are the cheapest, densest lines.
    @Test func aTightBudgetDropsTransactionsBeforeSummary() {
        let lines = bundle(transactions: 200).promptLines(for: .offDevice, budget: 600)
        #expect(!lines.contains("Merchant 150"))
        #expect(lines.contains("income 8000"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter ContextBundleTests`
Expected: FAIL to compile, `ContextBundle` not found.

- [ ] **Step 3: Implement ContextBundle**

```swift
import Foundation

/// Everything the coach may see about this user, assembled on the device per
/// request. The server uses it for one completion and discards it; nothing
/// here is ever stored remotely, which is the standing rule for user data
/// (see the plaid_items migration).
public struct ContextBundle: Sendable {

    public struct Money: Sendable, Equatable {
        public struct Transaction: Sendable, Equatable {
            public let merchant: String
            public let category: String?
            public let amount: Double
            public let date: Date

            public init(merchant: String, category: String?, amount: Double, date: Date) {
                self.merchant = merchant
                self.category = category
                self.amount = amount
                self.date = date
            }
        }

        public let income: Double
        public let expenses: Double
        public let savingsRate: Double?
        public let netWorth: Double?
        public let recent: [Transaction]

        public init(income: Double, expenses: Double, savingsRate: Double?,
                    netWorth: Double?, recent: [Transaction]) {
            self.income = income
            self.expenses = expenses
            self.savingsRate = savingsRate
            self.netWorth = netWorth
            self.recent = recent
        }
    }

    public struct Sector: Sendable, Equatable {
        public let name: String
        public let score: Int?
        public let delta: Int?

        public init(name: String, score: Int?, delta: Int?) {
            self.name = name
            self.score = score
            self.delta = delta
        }
    }

    public let digest: MetricsDigest
    public let money: Money?
    public let sectors: [Sector]
    public let firstName: String?

    public init(digest: MetricsDigest, money: Money? = nil,
                sectors: [Sector] = [], firstName: String? = nil) {
        self.digest = digest
        self.money = money
        self.sectors = sectors
        self.firstName = firstName
    }

    /// Renders the bundle for one audience within a character budget.
    ///
    /// `.onDevice` keeps the render to the digest plus one sector line: the
    /// local window is small and a transaction list would push the health
    /// data out of it. `.offDevice` carries everything, and trims the
    /// cheapest-to-lose detail first: transactions, oldest last.
    public func promptLines(for audience: MetricsDigest.Audience, budget: Int = 8_000) -> String {
        var blocks: [String] = []
        if let firstName { blocks.append("User: \(firstName)") }
        blocks.append(digest.promptLines(for: audience))

        if !sectors.isEmpty {
            let scores = sectors.map { sector in
                guard let score = sector.score else { return "\(sector.name) unscored" }
                let delta = sector.delta.map { $0 >= 0 ? " (+\($0))" : " (\($0))" } ?? ""
                return "\(sector.name) \(score)\(delta)"
            }
            blocks.append("Life sectors: " + scores.joined(separator: ", "))
        }

        if let money {
            var line = "Money this month: income \(Int(money.income)), expenses \(Int(money.expenses))"
            if let rate = money.savingsRate { line += ", saved \(Int(rate * 100))%" }
            if let netWorth = money.netWorth { line += ", net worth \(Int(netWorth))" }
            blocks.append(line)

            if audience == .offDevice {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                var rows: [String] = []
                var spent = blocks.joined(separator: "\n").count
                for transaction in money.recent {
                    let row = "\(formatter.string(from: transaction.date)) \(transaction.merchant)"
                        + (transaction.category.map { " (\($0))" } ?? "")
                        + " \(String(format: "%.2f", transaction.amount))"
                    guard spent + row.count + 1 <= budget else { break }
                    rows.append(row)
                    spent += row.count + 1
                }
                if !rows.isEmpty {
                    blocks.append("Recent transactions:\n" + rows.joined(separator: "\n"))
                }
            }
        }

        return blocks.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter ContextBundleTests`
Expected: PASS, all 3.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/Context/ContextBundle.swift LifeOSKit/Tests/InsightsTests/ContextBundleTests.swift
git commit -m "feat(coach): device-assembled context bundle with audience renders"
```

---

### Task 6: AnswerTask reads the bundle; the app assembles it

**Files:**
- Modify: `LifeOSKit/Sources/Insights/CoachTask.swift` (AnswerTask only; BriefTask keeps `MetricsDigest`)
- Modify: `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift`
- Modify: `LIfeOS/App/RootView.swift` (one line where `coach` gets its context attached, around `attachAll()`)
- Test: `LifeOSKit/Tests/InsightsTests/CoachTaskTests.swift`

**Interfaces:**
- Consumes: `ContextBundle` (Task 5), audience-threaded `prompt` (Task 1).
- Produces: `AnswerTask.Context == ContextBundle`. `CoachViewModel` gains `var bundleExtras: (@MainActor () -> (money: ContextBundle.Money?, sectors: [ContextBundle.Sector], firstName: String?))?` that RootView sets. Task 8 relies on `send(_:)` building the bundle.

- [ ] **Step 1: Write the failing test**

Append to `CoachTaskTests.swift`:

```swift
@Test func theAnswerTaskRendersTheWholeBundleOffDevice() {
    let bundle = ContextBundle(
        digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
        money: ContextBundle.Money(income: 100, expenses: 50, savingsRate: nil,
                                   netWorth: nil, recent: []),
        sectors: [ContextBundle.Sector(name: "Body", score: 8, delta: nil)],
        firstName: nil
    )
    let task = AnswerTask(question: "Am I saving?")
    let remote = task.prompt(bundle, for: .offDevice)
    #expect(remote.contains("income 100"))
    #expect(remote.contains("Body 8"))
    #expect(remote.contains("Am I saving?"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LifeOSKit && swift test --filter CoachTaskTests`
Expected: FAIL to compile ("cannot convert ContextBundle to MetricsDigest").

- [ ] **Step 3: Retarget AnswerTask**

In `CoachTask.swift`:

```swift
public struct AnswerTask: CoachTask {
    public typealias Output = CoachAnswer
    public typealias Context = ContextBundle

    public let question: String

    public init(question: String) {
        self.question = question
    }

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You answer questions about one person's life: their health metrics,
        money, and life-sector scores.
        Cite only numbers that appear in the data given to you. If the data
        does not contain the answer, say so plainly rather than guessing.
        """
    }

    public func prompt(_ bundle: ContextBundle, for audience: MetricsDigest.Audience) -> String {
        """
        Here is what their data shows:

        \(bundle.promptLines(for: audience))

        Question: \(question)
        """
    }
}
```

Fix the earlier Task 1 test (`theOffDeviceRenderCarriesNoRawSeries`) to wrap its digest: `task.prompt(ContextBundle(digest: digest), for: .onDevice)`.

- [ ] **Step 4: Wire the assembly in the app**

In `CoachViewModel.swift`, add the property and use it in `send(_:)`:

```swift
    /// Set by RootView; pulls the money and sector context that live in other
    /// view models. A closure rather than references, so the coach does not
    /// hold screens it never renders.
    var bundleExtras: (@MainActor () -> (money: ContextBundle.Money?,
                                         sectors: [ContextBundle.Sector],
                                         firstName: String?))?
```

In `send(_:)`, replace the digest construction's last line (`let result = await router.run(AnswerTask(question: question), digest)`) with:

```swift
            let extras = bundleExtras?()
            let bundle = ContextBundle(
                digest: digest,
                money: extras?.money,
                sectors: extras?.sectors ?? [],
                firstName: extras?.firstName
            )
            let result = await router.run(AnswerTask(question: question), bundle)
```

In `RootView.swift`, inside the existing `.task { attachAll() ... }` block (after `life.attach(context)`), attach the extras:

```swift
        coach.bundleExtras = { [weak money, weak life] in
            let snapshot = money?.snapshot
            return (
                money: snapshot.map { snap in
                    ContextBundle.Money(
                        income: snap.income,
                        expenses: snap.expenses,
                        savingsRate: snap.savingsRate,
                        netWorth: snap.netWorth,
                        recent: snap.recent.prefix(30).map {
                            ContextBundle.Money.Transaction(
                                merchant: $0.merchant, category: $0.category,
                                amount: $0.amount, date: $0.date)
                        }
                    )
                },
                sectors: (life?.cards ?? []).map { card in
                    ContextBundle.Sector(
                        name: card.sector.title, score: card.score,
                        delta: card.history.count > 1
                            ? zip(card.history.suffix(2).map(\.value),
                                  card.history.suffix(1).map(\.value)).first.map { $1 - $0 }
                            : nil)
                },
                firstName: nil
            )
        }
```

Note: `coach` is declared in `RootView`; if `money`/`life` are not weak-capturable (they are `@State` structs holding classes), capture them directly without `weak` and drop the optionals. Follow what compiles cleanly; the shape that matters is the tuple.

- [ ] **Step 5: Run the kit suite and build the app**

Run: `cd LifeOSKit && swift test && cd .. && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: tests PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit LIfeOS
git commit -m "feat(coach): answer over the full context bundle"
```

---

### Task 7: RemoteWire, RemoteEngine, and the router's error mapping

**Files:**
- Create: `LifeOSKit/Sources/Insights/Engines/RemoteEngine.swift`
- Modify: `LifeOSKit/Sources/Insights/CoachRouter.swift` (`runRemote` catch block)
- Modify: `LifeOSKit/Sources/Insights/Tasks/CoachAnswer.swift` (add `Decodable`)
- Modify: `LifeOSKit/Sources/Insights/CoachTask.swift` (add `remoteName`)
- Test: `LifeOSKit/Tests/InsightsTests/RemoteEngineTests.swift`
- Test: `LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift` (two new cases)

**Interfaces:**
- Consumes: Task 4's response contract, `AnswerTask` from Task 6.
- Produces: `RemoteEngine(baseURL:anonKey:tokenProvider:session:)` conforming to `Engine`; `RemoteEngineError` (`exhausted`, `refused(String)`, `unavailable`, `notSignedIn`, `unsupportedTask`); `RemoteWire.request(...)` and `RemoteWire.result(data:status:)`. Task 8 constructs the engine.

- [ ] **Step 1: Write the failing tests**

`RemoteEngineTests.swift`:

```swift
import Foundation
import Testing
@testable import Insights

struct RemoteEngineTests {
    private let base = URL(string: "https://example.supabase.co")!

    @Test func theRequestCarriesTaskPromptAndBothKeys() throws {
        let request = try RemoteWire.request(
            baseURL: base, anonKey: "anon-key", accessToken: "jwt-token",
            taskName: "answer", prompt: "Question: hi")
        #expect(request.url?.path.hasSuffix("/functions/v1/lifo-agent") == true)
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["task": "answer", "prompt": "Question: hi"])
    }

    @Test func aGoodReplyDecodesIntoTheOutputType() throws {
        let data = Data(#"{"output":{"answer":"Seven hours."},"tokens":300}"#.utf8)
        let answer: CoachAnswer = try RemoteWire.result(data: data, status: 200)
        #expect(answer.answer == "Seven hours.")
    }

    @Test func theBudgetStopIsItsOwnError() {
        let data = Data(#"{"error":"exhausted"}"#.utf8)
        #expect(throws: RemoteEngineError.exhausted) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 429)
        }
    }

    @Test func aRefusalCarriesTheModelsWords() {
        let data = Data(#"{"error":"refused","message":"Out of scope."}"#.utf8)
        #expect(throws: RemoteEngineError.refused("Out of scope.")) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 403)
        }
    }

    @Test func anythingElseIsUnavailable() {
        let data = Data(#"{"error":"upstream_failure"}"#.utf8)
        #expect(throws: RemoteEngineError.unavailable) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 502)
        }
    }
}
```

Append to `CoachRouterTests.swift`, inside the `@Suite`, using its existing `router(onDevice:remote:availability:)` helper and `brief`/`empty` fixtures (note: its `StubEngine` throws from the `remote` closure, and `availability: .unavailablePermanently` forces the remote path):

```swift
@Test func aRemoteExhaustionSurfacesAsExhausted() async {
    let result = await router(
        onDevice: { self.brief },
        remote: { throw RemoteEngineError.exhausted },
        availability: .unavailablePermanently
    ).run(BriefTask(), empty)
    #expect(result == .exhausted)
}

@Test func aRemoteRefusalSurfacesWithItsMessage() async {
    let result = await router(
        onDevice: { self.brief },
        remote: { throw RemoteEngineError.refused("Out of scope.") },
        availability: .unavailablePermanently
    ).run(BriefTask(), empty)
    #expect(result == .refused("Out of scope."))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter RemoteEngineTests`
Expected: FAIL to compile, `RemoteWire` not found.

- [ ] **Step 3: Implement**

`CoachAnswer.swift` — add the conformance (the macro does not provide it):

```swift
extension CoachAnswer: Decodable {}
```

(If the memberwise key does not line up, add explicit `CodingKeys` with `case answer`.)

`CoachTask.swift` — add to the protocol and tasks:

```swift
    /// The server-side name of this task, or nil when the task never leaves
    /// the device. The model and schema for a name live in the Edge Function.
    var remoteName: String? { get }
```

with `public var remoteName: String? { "answer" }` on `AnswerTask` and `public var remoteName: String? { nil }` on `BriefTask`.

`RemoteEngine.swift`:

```swift
import Foundation

public enum RemoteEngineError: Error, Equatable {
    case exhausted
    case refused(String)
    case unavailable
    case notSignedIn
    case unsupportedTask
}

/// The wire format, kept off the engine so a test can reach every decision
/// without a network. The engine is transport.
public enum RemoteWire {
    public static func request(
        baseURL: URL, anonKey: String, accessToken: String,
        taskName: String, prompt: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/lifo-agent"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "task": taskName, "prompt": prompt,
        ])
        return request
    }

    public static func result<Output: Decodable>(data: Data, status: Int) throws -> Output {
        struct Reply<T: Decodable>: Decodable { let output: T }
        struct Failure: Decodable { let error: String; let message: String? }

        guard (200..<300).contains(status) else {
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            switch (status, failure?.error) {
            case (429, _), (_, "exhausted"): throw RemoteEngineError.exhausted
            case (403, _), (_, "refused"): throw RemoteEngineError.refused(failure?.message ?? "LIFO declined that one.")
            default: throw RemoteEngineError.unavailable
            }
        }
        return try JSONDecoder().decode(Reply<Output>.self, from: data).output
    }
}

/// The cloud tier. Sends the off-device render of a task to the lifo-agent
/// Edge Function and decodes the structured reply.
public struct RemoteEngine: Engine {
    private let baseURL: URL
    private let anonKey: String
    private let tokenProvider: @Sendable () -> String?
    private let session: URLSession

    public init(baseURL: URL, anonKey: String,
                tokenProvider: @escaping @Sendable () -> String?,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public func run<T: CoachTask>(_ task: T, _ context: T.Context) async throws -> T.Output {
        guard let name = task.remoteName else { throw RemoteEngineError.unsupportedTask }
        guard let decodable = T.Output.self as? any Decodable.Type else {
            throw RemoteEngineError.unsupportedTask
        }
        guard let token = tokenProvider() else { throw RemoteEngineError.notSignedIn }

        let request = try RemoteWire.request(
            baseURL: baseURL, anonKey: anonKey, accessToken: token,
            taskName: name, prompt: task.prompt(context, for: .offDevice))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        func decode<D: Decodable>(_: D.Type) throws -> D {
            try RemoteWire.result(data: data, status: status)
        }
        guard let output = try decode(decodable) as? T.Output else {
            throw RemoteEngineError.unavailable
        }
        return output
    }
}
```

`CoachRouter.swift` — in `runRemote`, replace the bare `catch` with:

```swift
        } catch RemoteEngineError.exhausted {
            return .exhausted
        } catch RemoteEngineError.refused(let reason) {
            return .refused(reason)
        } catch {
            return fallback
        }
```

- [ ] **Step 4: Run the kit suite**

Run: `cd LifeOSKit && swift test`
Expected: PASS, including the two new router cases.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit
git commit -m "feat(coach): remote engine over the lifo-agent function"
```

---

### Task 8: Wire it, deploy it, prove it

**Files:**
- Modify: `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift` (the `router` property)

**Interfaces:**
- Consumes: everything above; `AppConfig.supabaseURL`, `AppConfig.supabaseAnonKey`, `KeychainAuthSessionStore` (Integrations).

- [ ] **Step 1: Fill the remote slot**

In `CoachViewModel.swift`, replace `private let router = CoachRouter(onDevice: OnDeviceEngine(), remote: nil)` with:

```swift
    private let router: CoachRouter = {
        var remote: (any Engine)?
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            remote = RemoteEngine(baseURL: url, anonKey: key, tokenProvider: {
                KeychainAuthSessionStore().load()?.accessToken
            })
        }
        return CoachRouter(onDevice: OnDeviceEngine(), remote: remote)
    }()
```

(`KeychainAuthSessionStore` lives in Integrations, already imported. Session refresh is owned by AppShell's foreground restore; reading the stored token per call is the same trust the sync paths use.)

- [ ] **Step 2: Full local verification**

Run: `cd LifeOSKit && swift test && cd .. && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3 && deno test supabase/functions/_shared/`
Expected: all suites PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Deploy the backend**

The `OPENAI_API_KEY` secret must exist first — if `supabase secrets list` does not show it, stop and ask the user to run `! supabase secrets set OPENAI_API_KEY=sk-...`.

Run:
```bash
supabase db push
supabase functions deploy lifo-agent
supabase functions list | grep lifo-agent
```
Expected: migration `20260827090000` applied; `lifo-agent` ACTIVE.

- [ ] **Step 4: Smoke the deployed function directly**

```bash
curl -s -X POST "https://abxwxpwhkcqtotjqsmxb.supabase.co/functions/v1/lifo-agent" \
  -H "Content-Type: application/json" -d '{"task":"answer","prompt":"hi"}' | head -c 200
```
Expected: `{"error":"unauthorized"}` — the gate works without a JWT. (A signed-in end-to-end run happens from the simulator: launch the app, sign in, ask LIFO a question; the reply should now come from the cloud path when Apple Intelligence is unavailable in the simulator.)

- [ ] **Step 5: Commit and merge**

```bash
git add LIfeOS
git commit -m "feat(coach): route LIFO through the remote engine"
```

Then finish the branch with the superpowers:finishing-a-development-branch skill (tests green, merge to main, clean up the worktree).
