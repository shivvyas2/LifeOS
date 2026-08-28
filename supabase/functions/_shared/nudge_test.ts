import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  COOLDOWN_DAYS,
  cooledDown,
  evaluate,
  formatHours,
  localDay,
  localHour,
  type MetricRow,
  type NudgeInput,
  phrasePrompt,
  QUIET_END,
  QUIET_START,
  SEND_HOUR,
  shiftDay,
  shortSleep,
  shouldConsider,
  stepsCollapsing,
  streakAtRisk,
  strongWeek,
  type WorkoutRow,
} from "./nudge.ts";

const TODAY = "2026-08-28";

/// Builds `count` days of metrics ending at `end`, most recent first, from a
/// function of how many days back the day is.
function history(
  end: string,
  count: number,
  build: (daysBack: number) => Partial<Omit<MetricRow, "date">>,
): MetricRow[] {
  return Array.from({ length: count }, (_, index) => ({
    date: shiftDay(end, -index),
    steps: null,
    sleep_minutes: null,
    exercise_minutes: null,
    ...build(index),
  }));
}

function input(over: Partial<NudgeInput> = {}): NudgeInput {
  return {
    metrics: [],
    workouts: [],
    log: [],
    today: TODAY,
    timeZone: "America/New_York",
    ...over,
  };
}

// ---------------------------------------------------------------------------
// Day arithmetic
// ---------------------------------------------------------------------------

Deno.test("days shift across month and year boundaries", () => {
  const cases: [string, number, string][] = [
    ["2026-08-28", -1, "2026-08-27"],
    ["2026-09-01", -1, "2026-08-31"],
    ["2026-01-01", -1, "2025-12-31"],
    ["2026-02-28", 1, "2026-03-01"],
    ["2024-02-28", 1, "2024-02-29"],
    ["2026-08-28", -30, "2026-07-29"],
  ];
  for (const [day, delta, expected] of cases) {
    assertEquals(shiftDay(day, delta), expected, `${day} ${delta}`);
  }
});

Deno.test("a local hour is read in the user's zone, not the server's", () => {
  // 2026-08-28T12:00Z is 8am in New York, 9pm in Tokyo, and midnight in
  // Auckland, which is already the next day there. Auckland is the case that
  // matters most: the same instant is inside the send window for one user and
  // outside it for another, and it is not even the same date.
  const noonUTC = new Date("2026-08-28T12:00:00Z");
  assertEquals(localHour("America/New_York", noonUTC), 8);
  assertEquals(localHour("Asia/Tokyo", noonUTC), 21);
  assertEquals(localHour("Pacific/Auckland", noonUTC), 0);
  assertEquals(localDay("America/New_York", noonUTC), "2026-08-28");
  assertEquals(localDay("Pacific/Auckland", noonUTC), "2026-08-29");
});

Deno.test("an unrecognised timezone yields no hour rather than UTC", () => {
  assertEquals(localHour("Mars/Olympus_Mons", new Date()), null);
  assertEquals(localDay("Mars/Olympus_Mons", new Date()), null);
});

// ---------------------------------------------------------------------------
// Volume rules
// ---------------------------------------------------------------------------

Deno.test("only the send hour is considered, and never outside the quiet window", () => {
  assertEquals(shouldConsider(SEND_HOUR), true);
  assertEquals(shouldConsider(SEND_HOUR + 1), false);
  assertEquals(shouldConsider(null), false);
  for (const hour of [0, 3, 6, 22, 23]) {
    assertEquals(shouldConsider(hour), false, `hour ${hour}`);
  }
  // The floor holds independently of the preference.
  assertEquals(SEND_HOUR >= QUIET_START && SEND_HOUR <= QUIET_END, true);
});

Deno.test("a trigger inside the cooldown is blocked, one outside it is not", () => {
  const log = [
    { trigger: "short_sleep", sent_at: `${shiftDay(TODAY, -2)}T08:00:00Z` },
    { trigger: "steps_collapsing", sent_at: `${shiftDay(TODAY, -COOLDOWN_DAYS)}T08:00:00Z` },
  ];
  const blocked = cooledDown(log, TODAY);
  assertEquals(blocked.has("short_sleep"), true);
  assertEquals(blocked.has("steps_collapsing"), false);
});

// ---------------------------------------------------------------------------
// Short sleep
// ---------------------------------------------------------------------------

Deno.test("three short nights against the person's own baseline fire", () => {
  const metrics = history(TODAY, 31, (back) => ({
    sleep_minutes: back < 3 ? 300 : 450,
  }));
  const fired = shortSleep(input({ metrics }));
  assertNotEquals(fired, null);
  assertEquals(fired!.name, "short_sleep");
  assertEquals(fired!.facts.average_minutes, 300);
  assertEquals(fired!.facts.baseline_minutes, 450);
  assertEquals(fired!.facts.deficit_minutes, 150);
});

Deno.test("a habitual short sleeper is not told they are failing", () => {
  // Six hours every night, for weeks. Nothing has changed, so nothing is worth
  // interrupting them over: this is the case a fixed seven hour target gets
  // wrong every single day.
  const metrics = history(TODAY, 31, () => ({ sleep_minutes: 360 }));
  assertEquals(shortSleep(input({ metrics })), null);
});

Deno.test("two short nights are not three", () => {
  const metrics = history(TODAY, 31, (back) => ({
    sleep_minutes: back < 2 ? 300 : 450,
  }));
  assertEquals(shortSleep(input({ metrics })), null);
});

Deno.test("a phone that has not synced does not fire a sleep nudge", () => {
  // Only the three recent nights exist. A missing day must never read as a
  // zero, and three nights is not a baseline.
  const metrics = history(TODAY, 3, () => ({ sleep_minutes: 300 }));
  assertEquals(shortSleep(input({ metrics })), null);
});

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

Deno.test("steps collapsing against the trailing fortnight fires", () => {
  const metrics = history(TODAY, 17, (back) => ({
    steps: back < 3 ? 2000 : 9000,
  }));
  const fired = stepsCollapsing(input({ metrics }));
  assertNotEquals(fired, null);
  assertEquals(fired!.facts.recent_steps, 2000);
  assertEquals(fired!.facts.baseline_steps, 9000);
  assertEquals(fired!.facts.drop_percent, 78);
});

Deno.test("a mild dip is not a collapse", () => {
  const metrics = history(TODAY, 17, (back) => ({
    steps: back < 3 ? 7000 : 9000,
  }));
  assertEquals(stepsCollapsing(input({ metrics })), null);
});

Deno.test("someone who does not carry their phone is not nudged about steps", () => {
  const metrics = history(TODAY, 17, (back) => ({
    steps: back < 3 ? 100 : 900,
  }));
  assertEquals(stepsCollapsing(input({ metrics })), null);
});

// ---------------------------------------------------------------------------
// Streaks
// ---------------------------------------------------------------------------

function workoutsOn(days: string[]): WorkoutRow[] {
  // Midday local, so the instant lands on the intended day in the test zone.
  return days.map((day) => ({ started_at: `${day}T16:00:00Z` }));
}

Deno.test("a streak counted back from yesterday fires, since nobody has trained at 8am", () => {
  const days = [1, 2, 3, 4].map((back) => shiftDay(TODAY, -back));
  const fired = streakAtRisk(input({ workouts: workoutsOn(days) }));
  assertNotEquals(fired, null);
  assertEquals(fired!.facts.streak_days, 4);
});

Deno.test("having already trained today means nothing is at risk", () => {
  const days = [0, 1, 2, 3].map((back) => shiftDay(TODAY, -back));
  assertEquals(streakAtRisk(input({ workouts: workoutsOn(days) })), null);
});

Deno.test("two days is not yet a streak worth interrupting someone over", () => {
  const days = [1, 2].map((back) => shiftDay(TODAY, -back));
  assertEquals(streakAtRisk(input({ workouts: workoutsOn(days) })), null);
});

Deno.test("a gap ends the streak", () => {
  const days = [2, 3, 4, 5].map((back) => shiftDay(TODAY, -back));
  assertEquals(streakAtRisk(input({ workouts: workoutsOn(days) })), null);
});

// ---------------------------------------------------------------------------
// The positive
// ---------------------------------------------------------------------------

Deno.test("a genuinely strong week fires", () => {
  const metrics = history(TODAY, 28, (back) => ({
    steps: back < 7 ? 13000 : 8000,
  }));
  const fired = strongWeek(input({ metrics }));
  assertNotEquals(fired, null);
  assertEquals(fired!.facts.gain_percent, 63);
});

Deno.test("a personal best fires even without a strong week behind it", () => {
  const metrics = history(TODAY, 93, (back) => ({
    steps: back === 1 ? 21000 : 8000,
  }));
  const fired = strongWeek(input({ metrics }));
  assertNotEquals(fired, null);
  assertEquals(fired!.facts.peak_steps, 21000);
  assertEquals(fired!.facts.previous_best_steps, 8000);
});

Deno.test("the first good day anyone logs is not a personal best", () => {
  const metrics = history(TODAY, 5, (back) => ({ steps: back === 1 ? 21000 : 8000 }));
  assertEquals(strongWeek(input({ metrics })), null);
});

// ---------------------------------------------------------------------------
// Choosing one
// ---------------------------------------------------------------------------

Deno.test("nothing to say is the common outcome and yields no nudge", () => {
  const metrics = history(TODAY, 31, () => ({ steps: 8000, sleep_minutes: 450 }));
  assertEquals(evaluate(input({ metrics })), null);
});

Deno.test("the positive wins when it fires, so the channel is not only bad news", () => {
  // Both fire: steps are well up on the baseline, and the last three nights
  // are well down on it.
  const metrics = history(TODAY, 31, (back) => ({
    steps: back < 7 ? 13000 : 8000,
    sleep_minutes: back < 3 ? 300 : 450,
  }));
  const fired = evaluate(input({ metrics }));
  assertEquals(fired!.name, "strong_week");
});

Deno.test("a cooled down winner steps aside for the next thing worth saying", () => {
  const metrics = history(TODAY, 31, (back) => ({
    steps: back < 7 ? 13000 : 8000,
    sleep_minutes: back < 3 ? 300 : 450,
  }));
  const log = [{ trigger: "strong_week", sent_at: `${shiftDay(TODAY, -1)}T08:00:00Z` }];
  const fired = evaluate(input({ metrics, log }));
  assertEquals(fired!.name, "short_sleep");
});

// ---------------------------------------------------------------------------
// Phrasing and fallbacks
// ---------------------------------------------------------------------------

Deno.test("every fired trigger carries a sendable sentence, so an outage loses nothing", () => {
  const metrics = history(TODAY, 31, (back) => ({ sleep_minutes: back < 3 ? 300 : 450 }));
  const fired = shortSleep(input({ metrics }))!;
  assertEquals(fired.fallback.length > 0, true);
  assertEquals(fired.fallback.length < 180, true);
  // The prohibitions the conversational style already carries apply to a
  // sentence that arrives on a lock screen just as much.
  for (const banned of ["*", "_", "`", "#", "—", "–"]) {
    assertEquals(fired.fallback.includes(banned), false, `fallback contains ${banned}`);
  }
});

Deno.test("the phrasing prompt carries the numbers and forbids inventing more", () => {
  const metrics = history(TODAY, 31, (back) => ({ sleep_minutes: back < 3 ? 300 : 450 }));
  const prompt = phrasePrompt(shortSleep(input({ metrics }))!);
  assertEquals(prompt.includes("baseline_minutes: 450"), true);
  assertEquals(prompt.includes("Do not invent"), true);
  // Small by construction: the trigger already did the arithmetic.
  assertEquals(prompt.length < 700, true);
});

Deno.test("hours read the way a person says them", () => {
  assertEquals(formatHours(300), "5h");
  assertEquals(formatHours(450), "7h 30m");
  assertEquals(formatHours(455), "7h 35m");
});
