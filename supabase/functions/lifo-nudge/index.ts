import { json, serviceClient } from "../_shared/supabase.ts";
import {
  classifyOpenAIFailure,
  LifoRefusal,
  NUDGE_TOKEN_CAP,
  openAIBody,
  parseOutput,
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

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!isAuthorized(req)) return json({ error: "unauthorized" }, 401);

  const apns = apnsConfigFromEnv();
  // Not an error. A deployment without APNs keys should evaluate nothing and
  // send nothing rather than fail hourly and fill the logs.
  if (!apns) {
    console.log("lifo-nudge skipped: apns not configured");
    return json({ considered: 0, sent: 0, reason: "apns_not_configured" }, 200);
  }

  const db = serviceClient();
  const now = new Date();

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

    const payload = notificationPayload(text, fired.name, due.day);
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
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return fallback;

  const { data: usage } = await db
    .from("lifo_usage")
    .select("tokens")
    .eq("user_id", userID)
    .eq("day", new Date().toISOString().slice(0, 10))
    .eq("kind", "nudge")
    .maybeSingle();
  if ((usage?.tokens ?? 0) >= NUDGE_TOKEN_CAP) return fallback;

  let reply: Response;
  try {
    reply = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(openAIBody("nudge", prompt)),
    });
  } catch {
    console.error("lifo-nudge openai fetch failed");
    return fallback;
  }
  if (!reply.ok) {
    console.error(`lifo-nudge openai failed status=${reply.status} kind=${classifyOpenAIFailure(reply.status)}`);
    return fallback;
  }

  const body = await reply.json();
  const tokens = (body as { usage?: { total_tokens?: number } })?.usage?.total_tokens ?? 0;
  // Debited on every path that got as far as a billable call, exactly as the
  // chat path does, and against the nudge kind so it cannot eat chat's budget.
  const { error: debitError } = await db.rpc("lifo_debit", {
    p_user: userID,
    p_tokens: tokens,
    p_kind: "nudge",
  });
  if (debitError) console.error(`lifo-nudge debit failed: ${debitError.code}`);

  try {
    const { output } = parseOutput("nudge", body);
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
