// The decision half of the proactive nudge: when LIFO has something worth
// saying, which thing it is, and what it falls back to when the model cannot
// be reached. Pure functions only, so every one of these judgements is
// testable without a network, a clock, or a database. lifo-nudge/index.ts
// owns the door (cron, rows, model call, APNs).
//
// A trigger is a pure function from rows to an optional fired result. That is
// the same shape EscalationPolicy.disposition and SectorEvidenceFactory.evidence
// already use on the device, and it is what keeps the interesting logic here
// rather than tangled into the send.

// ---------------------------------------------------------------------------
// Rows, as the server actually has them
// ---------------------------------------------------------------------------

/// One row of `daily_metrics`, narrowed to the columns a trigger reads.
export interface MetricRow {
  /// `YYYY-MM-DD`, the local day the metrics were attributed to.
  date: string;
  steps: number | null;
  sleep_minutes: number | null;
  exercise_minutes: number | null;
}

/// One row of `workout_records`, narrowed the same way. `started_at` is an
/// instant; the day it belongs to is resolved against the user's timezone
/// before a streak is counted, because a 9pm workout in Auckland is a
/// different day from the same instant in Los Angeles.
export interface WorkoutRow {
  started_at: string;
}

/// One row of `nudge_log`, for the per-trigger cooldown.
export interface NudgeLogRow {
  trigger: string;
  sent_at: string;
}

export type TriggerName =
  | "strong_week"
  | "short_sleep"
  | "steps_collapsing"
  | "streak_at_risk";

/// A fired trigger carries the numbers that made it fire and a sentence that
/// can be sent without a model.
///
/// The fallback is not a nicety. It is what gets delivered when OpenAI is
/// unreachable, and without it an outage silently swallows the observation
/// instead of delivering it plainly.
export interface FiredTrigger {
  name: TriggerName;
  facts: Record<string, number>;
  fallback: string;
}

export interface NudgeInput {
  metrics: MetricRow[];
  workouts: WorkoutRow[];
  /// Recent sends, for the seven day per-trigger cooldown.
  log: NudgeLogRow[];
  /// The user's local day, `YYYY-MM-DD`. Every window below is counted back
  /// from here rather than from UTC midnight.
  today: string;
  timeZone: string;
}

// ---------------------------------------------------------------------------
// Volume rules
// ---------------------------------------------------------------------------

/// 8am local. Early enough to be about the day ahead, late enough not to be
/// the thing that wakes someone.
export const SEND_HOUR = 8;
/// Nothing ever sends outside these local hours, whatever the send hour is set
/// to. A nudge at the wrong hour is worse than no nudge.
export const QUIET_START = 7;
export const QUIET_END = 21;
/// Days before the same trigger may fire again. Without it the same
/// observation arrives on Tuesday and again on Thursday, which is how a
/// notification channel gets switched off.
export const COOLDOWN_DAYS = 7;

/// The user's local hour, from a timezone name. Returns null for a name the
/// runtime does not recognise, which is treated as "do not send" by the
/// caller rather than defaulting to UTC.
export function localHour(timeZone: string, now: Date): number | null {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hour: "numeric",
      hour12: false,
    }).formatToParts(now);
    const hour = parts.find((part) => part.type === "hour")?.value;
    if (hour === undefined) return null;
    const parsed = Number(hour);
    // `hour12: false` yields 24 for midnight in some ICU versions.
    return parsed === 24 ? 0 : parsed;
  } catch {
    return null;
  }
}

/// The user's local calendar day as `YYYY-MM-DD`.
export function localDay(timeZone: string, now: Date): string | null {
  try {
    // `en-CA` formats as YYYY-MM-DD, which is the shape every date column and
    // every window below already uses.
    return new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now);
  } catch {
    return null;
  }
}

/// Whether this hourly run should consider this user at all.
///
/// Two separate conditions, deliberately not collapsed: the send hour is a
/// preference and the quiet window is a floor. Widening the first must never
/// be able to breach the second.
export function shouldConsider(hour: number | null): boolean {
  if (hour === null) return false;
  if (hour < QUIET_START || hour > QUIET_END) return false;
  return hour === SEND_HOUR;
}

// ---------------------------------------------------------------------------
// Small statistics
// ---------------------------------------------------------------------------

function mean(values: number[]): number | null {
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

/// `YYYY-MM-DD` shifted by whole days, without going through a Date and its
/// timezone. The strings are already local days; reconstructing them through
/// UTC is how an off-by-one appears at the two hours a year it matters.
export function shiftDay(day: string, delta: number): string {
  const [year, month, date] = day.split("-").map(Number);
  const shifted = new Date(Date.UTC(year, month - 1, date + delta));
  return shifted.toISOString().slice(0, 10);
}

/// The `count` days ending at `end` inclusive, most recent first.
function window(end: string, count: number): string[] {
  return Array.from({ length: count }, (_, index) => shiftDay(end, -index));
}

function byDay(metrics: MetricRow[]): Map<string, MetricRow> {
  return new Map(metrics.map((row) => [row.date, row]));
}

/// Values for a run of days, dropping days with no row and days where the
/// column is null. A trigger that treated a missing day as a zero would fire
/// on a phone that simply had not synced.
function values(
  metrics: Map<string, MetricRow>,
  days: string[],
  column: keyof Omit<MetricRow, "date">,
): number[] {
  const out: number[] = [];
  for (const day of days) {
    const value = metrics.get(day)?.[column];
    if (typeof value === "number" && Number.isFinite(value)) out.push(value);
  }
  return out;
}

// ---------------------------------------------------------------------------
// The triggers
// ---------------------------------------------------------------------------

/// Three short nights running, judged against the person's own norm.
///
/// Not against a fixed seven hours: the server does not have `GoalTargets`,
/// which live only in SwiftData, and a fixed number tells a habitual six hour
/// sleeper they are failing every single day. The baseline is their own median
/// over the four weeks before the three nights being judged, so the trigger
/// says "short for you" rather than "short for someone".
export function shortSleep(input: NudgeInput): FiredTrigger | null {
  const metrics = byDay(input.metrics);
  const recent = values(metrics, window(input.today, 3), "sleep_minutes");
  if (recent.length < 3) return null;

  const baselineDays = window(shiftDay(input.today, -3), 28);
  const baselineValues = values(metrics, baselineDays, "sleep_minutes");
  // Fewer than two weeks of history is not a baseline, it is a guess.
  if (baselineValues.length < 14) return null;
  const baseline = median(baselineValues);
  if (baseline === null) return null;

  const short = baseline - 60;
  if (!recent.every((night) => night < short)) return null;

  const average = mean(recent) ?? 0;
  return {
    name: "short_sleep",
    facts: {
      nights: 3,
      average_minutes: Math.round(average),
      baseline_minutes: Math.round(baseline),
      deficit_minutes: Math.round(baseline - average),
    },
    fallback:
      `Three short nights in a row. You have averaged ${formatHours(average)} against your usual ${formatHours(baseline)}.`,
  };
}

/// Steps collapsing against the trailing fortnight.
export function stepsCollapsing(input: NudgeInput): FiredTrigger | null {
  const metrics = byDay(input.metrics);
  const recentValues = values(metrics, window(input.today, 3), "steps");
  if (recentValues.length < 3) return null;

  const baselineValues = values(metrics, window(shiftDay(input.today, -3), 14), "steps");
  if (baselineValues.length < 10) return null;

  const recent = mean(recentValues);
  const baseline = mean(baselineValues);
  if (recent === null || baseline === null) return null;
  // A baseline of near nothing makes any ratio meaningless, and someone who
  // does not carry their phone is not someone to nudge about steps.
  if (baseline < 2000) return null;
  if (recent >= baseline * 0.6) return null;

  return {
    name: "steps_collapsing",
    facts: {
      recent_steps: Math.round(recent),
      baseline_steps: Math.round(baseline),
      drop_percent: Math.round((1 - recent / baseline) * 100),
    },
    fallback:
      `Your last three days averaged ${Math.round(recent).toLocaleString("en-US")} steps against a usual ${Math.round(baseline).toLocaleString("en-US")}.`,
  };
}

/// A workout streak that today would break.
///
/// Counted back from yesterday, not from today: at eight in the morning
/// nobody has trained yet, so counting today would end every streak at zero
/// and the trigger would never fire.
export function streakAtRisk(input: NudgeInput): FiredTrigger | null {
  const days = workoutDays(input.workouts, input.timeZone);
  // Already trained today. Nothing is at risk and saying so would be wrong.
  if (days.has(input.today)) return null;

  let length = 0;
  let cursor = shiftDay(input.today, -1);
  while (days.has(cursor)) {
    length += 1;
    cursor = shiftDay(cursor, -1);
  }
  // Two days is not yet a streak worth protecting; interrupting someone over
  // one is how this channel earns its way into Settings.
  if (length < 3) return null;

  return {
    name: "streak_at_risk",
    facts: { streak_days: length },
    fallback: `You have trained ${length} days running. Today is the one that keeps it.`,
  };
}

/// The positive. Not decoration: a channel that only ever carries bad news
/// gets switched off, and then none of the rest of this matters.
///
/// Two ways to earn it, because a steady week and a single standout day are
/// both worth saying and neither subsumes the other.
export function strongWeek(input: NudgeInput): FiredTrigger | null {
  const metrics = byDay(input.metrics);

  const recentValues = values(metrics, window(input.today, 7), "steps");
  const baselineValues = values(metrics, window(shiftDay(input.today, -7), 21), "steps");
  if (recentValues.length >= 5 && baselineValues.length >= 14) {
    const recent = mean(recentValues);
    const baseline = mean(baselineValues);
    if (recent !== null && baseline !== null && baseline >= 2000 && recent >= baseline * 1.25) {
      return {
        name: "strong_week",
        facts: {
          recent_steps: Math.round(recent),
          baseline_steps: Math.round(baseline),
          gain_percent: Math.round((recent / baseline - 1) * 100),
        },
        fallback:
          `Strong week. You averaged ${Math.round(recent).toLocaleString("en-US")} steps a day against your usual ${Math.round(baseline).toLocaleString("en-US")}.`,
      };
    }
  }

  // A personal best in the last three days, measured against everything else
  // the server holds. Requires a real history behind it, or the first good
  // day anyone logs is a record.
  const recentDays = window(input.today, 3);
  const best = values(metrics, recentDays, "steps");
  const history = values(
    metrics,
    window(shiftDay(input.today, -3), 90),
    "steps",
  );
  if (best.length > 0 && history.length >= 21) {
    const peak = Math.max(...best);
    const previous = Math.max(...history);
    if (peak > previous) {
      return {
        name: "strong_week",
        facts: { peak_steps: peak, previous_best_steps: previous },
        fallback:
          `New best: ${peak.toLocaleString("en-US")} steps, past your previous ${previous.toLocaleString("en-US")}.`,
      };
    }
  }

  return null;
}

/// The local days a workout happened on.
function workoutDays(workouts: WorkoutRow[], timeZone: string): Set<string> {
  const days = new Set<string>();
  for (const workout of workouts) {
    const at = new Date(workout.started_at);
    if (Number.isNaN(at.getTime())) continue;
    const day = localDay(timeZone, at);
    if (day) days.add(day);
  }
  return days;
}

// ---------------------------------------------------------------------------
// Choosing one
// ---------------------------------------------------------------------------

/// Evaluated in this order, and the first that fires wins.
///
/// The positive is first on purpose. A genuinely strong week is rare, the
/// negatives are still true tomorrow, and the seven day cooldown means a
/// negative deferred today cannot be lost for longer than that. Put the
/// positive last and it never arrives, because there is almost always
/// something going less well.
const TRIGGERS: ((input: NudgeInput) => FiredTrigger | null)[] = [
  strongWeek,
  shortSleep,
  stepsCollapsing,
  streakAtRisk,
];

/// The one thing to say today, or nothing. Nothing is the common outcome and
/// a valid one.
export function evaluate(input: NudgeInput): FiredTrigger | null {
  const blocked = cooledDown(input.log, input.today);
  for (const trigger of TRIGGERS) {
    const fired = trigger(input);
    if (fired && !blocked.has(fired.name)) return fired;
  }
  return null;
}

/// Trigger names that fired inside the cooldown window and so may not fire
/// again yet.
export function cooledDown(log: NudgeLogRow[], today: string): Set<string> {
  const earliest = shiftDay(today, -(COOLDOWN_DAYS - 1));
  const blocked = new Set<string>();
  for (const row of log) {
    const day = row.sent_at.slice(0, 10);
    if (day >= earliest) blocked.add(row.trigger);
  }
  return blocked;
}

// ---------------------------------------------------------------------------
// Phrasing
// ---------------------------------------------------------------------------

/// The prompt that turns a fired trigger into a sentence.
///
/// The trigger already carries its numbers, so this is deliberately tiny: on
/// the order of 300 tokens in and 60 out. The model's whole job is phrasing,
/// which is why a rule decided whether to interrupt someone and a model only
/// decided how to word it.
export function phrasePrompt(fired: FiredTrigger): string {
  const facts = Object.entries(fired.facts)
    .map(([key, value]) => `${key}: ${value}`)
    .join("\n");
  return `Write one notification for this person, at most two sentences and under 180 characters.

Observation: ${fired.name}
${facts}

Use only these numbers. Do not invent any others. Do not greet them, do not sign off, and do not ask more than one question. Write it as something you noticed, not as an instruction.`;
}

/// Hours and minutes as a person says them, for the fallback sentences.
export function formatHours(minutes: number): string {
  const whole = Math.floor(minutes / 60);
  const rest = Math.round(minutes - whole * 60);
  if (rest === 0) return `${whole}h`;
  return `${whole}h ${rest}m`;
}

/// How wide a window of rows the caller has to fetch to evaluate everything
/// above. Stated here rather than in index.ts so a new trigger that reaches
/// further back cannot silently be starved of rows.
export const LOOKBACK_DAYS = 94;
