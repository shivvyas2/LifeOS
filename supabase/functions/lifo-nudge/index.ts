import Anthropic from "npm:@anthropic-ai/sdk@0.131.0";
import { json, serviceClient } from "../_shared/supabase.ts";
import {
  billedTokens,
  classifyFailure,
  LifoRefusal,
  NUDGE_TOKEN_CAP,
  parseOutput,
  taskBody,
} from "../_shared/lifo.ts";
import {
  apnsConfigFromEnv,
  notificationPayload,
  sendPush,
} from "../_shared/apns.ts";
import {
  evaluate,
  localDay,
  localHour,
  LOOKBACK_DAYS,
  type MetricRow,
  type NudgeLogRow,
  phrasePrompt,
  SEND_HOUR,
  shiftDay,
  shouldConsider,
  type WorkoutRow,
} from "../_shared/nudge.ts";

// The proactive half of LIFO. Run hourly by pg_cron; the send hour is local,
// so each run picks up whichever users have just reached 8am.
//
// This file owns the door only. Every decision (which trigger, whether it is
// cooled down, whether this hour counts) lives in _shared/nudge.ts as a pure
// function with a test beside it, which is the same division lifo.ts and
// lifo-agent already use.
//
// No message text is written to any table. nudge_log records that something
// was said and which observation it was about, never the sentence.

/// The device may not call this. It is cron talking to itself, and the only
/// caller that legitimately has the service role key is the scheduled job.
function isAuthorized(req: Request): boolean {
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!expected) return false;
  const header = req.headers.get("Authorization") ?? "";
  return header === `Bearer ${expected}`;
}

interface TokenRow {
  token: string;
  user_id: string;
  timezone: string;
}

/// A forced send, for proving delivery works.
///
/// Silence is the common outcome by design, so without this the only way to
/// find out whether the APNs half is wired correctly is to wait for a real
/// trigger to fire, which may be days and may never happen for a given
/// account. This bypasses the triggers, the cooldown, and the send hour.
///
/// It writes no `nudge_log` row and spends no model tokens, so a test send
/// cannot consume the day's real nudge. No new exposure either: it sits behind
/// the same service role gate as the rest of the function, and a caller with
/// that key can already do anything this does.
interface TestRequest {
  test_user_id: string;
  text?: string;
}

function parseTestRequest(body: unknown): TestRequest | null {
  if (typeof body !== "object" || body === null) return null;
  const candidate = body as Record<string, unknown>;
  if (typeof candidate.test_user_id !== "string") return null;
  return {
    test_user_id: candidate.test_user_id,
    text: typeof candidate.text === "string" ? candidate.text : undefined,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!isAuthorized(req)) return json({ error: "unauthorized" }, 401);

  // Read once: the body is consumed by whichever path takes it.
  const body = await req.json().catch(() => ({}));
  const test = parseTestRequest(body);

  const apns = apnsConfigFromEnv();
  // Not an error. A deployment without APNs keys should evaluate nothing and
  // send nothing rather than fail hourly and fill the logs.
  if (!apns) {
    console.log("lifo-nudge skipped: apns not configured");
    return json({ considered: 0, sent: 0, reason: "apns_not_configured" }, 200);
  }

  const db = serviceClient();
  const now = new Date();

  if (test) {
    const { data: rows, error } = await db
      .from("device_tokens")
      .select("token")
      .eq("user_id", test.test_user_id);
    if (error) {
      console.error(`lifo-nudge test lookup failed: ${error.code}`);
      return json({ error: "storage_failed" }, 500);
    }
    const targets = (rows ?? []) as { token: string }[];
    // The most useful answer when nothing arrives: the phone never registered.
    if (targets.length === 0) return json({ error: "no_device_tokens", sent: 0 }, 404);

    const text = test.text ?? "This is LIFO checking the line works.";
    const payload = notificationPayload(text, "test", now.toISOString().slice(0, 10), test.test_user_id);
    let sent = 0;
    const failures: number[] = [];
    for (const target of targets) {
      const result = await sendPush(apns, target.token, payload, now);
      if (result.unregistered) {
        await db.from("device_tokens").delete().eq("token", target.token);
      }
      if (result.status < 300) sent += 1;
      else failures.push(result.status);
    }
    return json({ tokens: targets.length, sent, failures }, 200);
  }

  const { data: tokens, error: tokenError } = await db
    .from("device_tokens")
    .select("token, user_id, timezone");
  if (tokenError) {
    console.error(`lifo-nudge token lookup failed: ${tokenError.code}`);
    return json({ error: "storage_failed" }, 500);
  }

  // Whose local clock says it is the send hour. A row whose timezone the
  // runtime does not recognise yields no hour and so never sends: a nudge at
  // the wrong hour is worse than no nudge.
  const dueByUser = new Map<string, { tokens: string[]; timeZone: string; day: string }>();
  for (const row of (tokens ?? []) as TokenRow[]) {
    if (!shouldConsider(localHour(row.timezone, now))) continue;
    const day = localDay(row.timezone, now);
    if (!day) continue;
    const existing = dueByUser.get(row.user_id);
    if (existing) {
      existing.tokens.push(row.token);
    } else {
      dueByUser.set(row.user_id, { tokens: [row.token], timeZone: row.timezone, day });
    }
  }
  if (dueByUser.size === 0) return json({ considered: 0, sent: 0 }, 200);

  const userIDs = [...dueByUser.keys()];
  // One query per table for the whole batch rather than three per user: at
  // eight in the morning in a populous timezone this loop is every user in
  // that zone at once.
  const earliestDay = shiftDay(
    [...dueByUser.values()].map((due) => due.day).sort()[0],
    -LOOKBACK_DAYS,
  );

  const [metricsReply, workoutsReply, logReply] = await Promise.all([
    db.from("daily_metrics")
      .select("user_id, date, steps, sleep_minutes, exercise_minutes")
      .in("user_id", userIDs)
      .gte("date", earliestDay),
    db.from("workout_records")
      .select("user_id, started_at")
      .in("user_id", userIDs)
      .gte("started_at", `${shiftDay(earliestDay, 0)}T00:00:00Z`),
    db.from("nudge_log")
      .select("user_id, trigger, sent_at")
      .in("user_id", userIDs)
      .gte("sent_at", `${shiftDay(earliestDay, 0)}T00:00:00Z`),
  ]);
  if (metricsReply.error || workoutsReply.error || logReply.error) {
    console.error("lifo-nudge row lookup failed");
    return json({ error: "storage_failed" }, 500);
  }

  const metrics = groupBy(metricsReply.data ?? [], (row) => row.user_id as string);
  const workouts = groupBy(workoutsReply.data ?? [], (row) => row.user_id as string);
  const log = groupBy(logReply.data ?? [], (row) => row.user_id as string);

  let sent = 0;
  // Sequential on purpose. The expensive step is one small model call per
  // firing user, firing is the uncommon case, and a burst of parallel APNs
  // connections is how a sender gets throttled.
  for (const [userID, due] of dueByUser) {
    const fired = evaluate({
      metrics: (metrics.get(userID) ?? []) as MetricRow[],
      workouts: (workouts.get(userID) ?? []) as WorkoutRow[],
      log: (log.get(userID) ?? []) as NudgeLogRow[],
      today: due.day,
      timeZone: due.timeZone,
    });
    // The common path, and a valid one. Silence costs nothing and reaches no
    // model.
    if (!fired) continue;

    // Claim the day before spending anything. Two overlapping cron runs both
    // reach here; the unique key on (user_id, day) means exactly one wins and
    // the other stops without sending a duplicate.
    const { error: claimError } = await db
      .from("nudge_log")
      .insert({ user_id: userID, day: due.day, trigger: fired.name });
    if (claimError) {
      // 23505 is unique_violation: another run already claimed today.
      if (claimError.code !== "23505") {
        console.error(`lifo-nudge claim failed: ${claimError.code}`);
      }
      continue;
    }

    const text = await phrase(db, userID, fired.fallback, phrasePrompt(fired));
    // A refusal is not routed around. It is the one failure that yields no
    // send at all, the same distinction EscalationPolicy draws between a
    // transient fault and a safety decision.
    if (text === null) {
      console.log(`lifo-nudge refused trigger=${fired.name}`);
      continue;
    }

    const payload = notificationPayload(text, fired.name, due.day, userID);
    for (const token of due.tokens) {
      const result = await sendPush(apns, token, payload, now);
      if (result.unregistered) {
        // Without this the job pushes at dead tokens indefinitely.
        await db.from("device_tokens").delete().eq("token", token);
      } else if (result.status < 300) {
        sent += 1;
      }
    }
    console.log(`lifo-nudge sent trigger=${fired.name} hour=${SEND_HOUR}`);
  }

  return json({ considered: dueByUser.size, sent }, 200);
});

/// The sentence, or the trigger's own fallback when the model cannot be
/// reached, or null when the model refuses.
///
/// The distinction matters: an outage must not silently swallow an
/// observation, and a refusal must not be routed around.
async function phrase(
  db: ReturnType<typeof serviceClient>,
  userID: string,
  fallback: string,
  prompt: string,
): Promise<string | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return fallback;

  const { data: usage } = await db
    .from("lifo_usage")
    .select("tokens")
    .eq("user_id", userID)
    .eq("day", new Date().toISOString().slice(0, 10))
    .eq("kind", "nudge")
    .maybeSingle();
  if ((usage?.tokens ?? 0) >= NUDGE_TOKEN_CAP) return fallback;

  let reply: Anthropic.Message;
  try {
    reply = await new Anthropic({ apiKey }).messages.create(taskBody("nudge", prompt));
  } catch (error) {
    if (error instanceof Anthropic.APIError && error.status !== undefined) {
      console.error(`lifo-nudge provider failed status=${error.status} kind=${classifyFailure(error.status)}`);
    } else {
      console.error("lifo-nudge provider call failed");
    }
    return fallback;
  }

  // Debited on every path that got as far as a billable call, exactly as the
  // chat path does, and against the nudge kind so it cannot eat chat's budget.
  const { error: debitError } = await db.rpc("lifo_debit", {
    p_user: userID,
    p_tokens: billedTokens(reply.usage),
    p_kind: "nudge",
  });
  if (debitError) console.error(`lifo-nudge debit failed: ${debitError.code}`);

  try {
    const { output } = parseOutput("nudge", reply);
    const text = output.text as string;
    return text.trim().length > 0 ? text.trim() : fallback;
  } catch (failure) {
    if (failure instanceof LifoRefusal) return null;
    console.error("lifo-nudge parse failed");
    return fallback;
  }
}

function groupBy<T>(rows: T[], key: (row: T) => string): Map<string, T[]> {
  const grouped = new Map<string, T[]>();
  for (const row of rows) {
    const id = key(row);
    const existing = grouped.get(id);
    if (existing) existing.push(row);
    else grouped.set(id, [row]);
  }
  return grouped;
}
