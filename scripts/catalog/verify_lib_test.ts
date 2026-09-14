import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { durationPlausible, parseCatalog, rowToSQL, titleMatches } from "./verify_lib.ts";

Deno.test("a row title must be a prefix of the oEmbed title, case and punctuation aside", () => {
  assertEquals(titleMatches("30 Min Pull Day", "30 MIN PULL DAY | Back & Biceps"), true);
  assertEquals(titleMatches("30 Min Push Day", "30 MIN PULL DAY | Back & Biceps"), false);
});

Deno.test("a stated length in the title must be within ten percent of the duration", () => {
  assertEquals(durationPlausible("30 Min Pull Day", 1780), true);
  assertEquals(durationPlausible("30 Min Pull Day", 2400), false);
  assertEquals(durationPlausible("Pull Day", 2400), true);
});

Deno.test("a row becomes one insert with arrays and a verified timestamp", () => {
  const sql = rowToSQL({
    youtube_id: "abc123XYZ_-", title: "30 Min Pull Day", channel: "Caroline Girvan", duration_s: 1780,
    goal: ["strength", "hypertrophy"], split: "pull", muscles: ["back", "biceps"], equipment: ["dumbbells"], intensity: 2,
  }, "2026-09-15T09:00:00Z");
  assertEquals(sql.includes("'abc123XYZ_-'"), true);
  assertEquals(sql.includes("array['strength','hypertrophy']"), true);
  assertEquals(sql.includes("'2026-09-15T09:00:00Z'"), true);
});

Deno.test("the catalog rejects unknown vocabulary and bad ids", () => {
  assertThrows(() => parseCatalog(JSON.stringify([{ youtube_id: "short", title: "x", channel: "c", duration_s: 60, goal: ["strength"], split: "push", muscles: [], equipment: [], intensity: 2 }])));
  assertThrows(() => parseCatalog(JSON.stringify([{ youtube_id: "abc123XYZ_-", title: "x", channel: "c", duration_s: 60, goal: ["cardio"], split: "push", muscles: [], equipment: [], intensity: 2 }])));
  assertEquals(parseCatalog(JSON.stringify([{ youtube_id: "abc123XYZ_-", title: "x", channel: "c", duration_s: 60, goal: ["strength"], split: "push", muscles: [], equipment: ["none"], intensity: 2 }])).length, 1);
});
