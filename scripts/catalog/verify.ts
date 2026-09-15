// Verifies every catalog row against YouTube's keyless oEmbed endpoint and
// writes the seed migration.
//
// Run: deno run --allow-net --allow-read --allow-write scripts/catalog/verify.ts [--out <path>]
//
// `--out` is how a curation pass after the first `supabase db push` reaches
// the server: the first seed is a migration Supabase has already recorded and
// will never re-run, so a later pass writes a new timestamped migration
// instead of silently rewriting the old one.
import { channelMatches, durationPlausible, parseCatalog, seedSQL, titleMatches } from "./verify_lib.ts";

const DEFAULT_OUT = "supabase/migrations/20260915090100_workout_videos_seed.sql";
const outFlag = Deno.args.indexOf("--out");
const out = outFlag === -1 ? DEFAULT_OUT : Deno.args[outFlag + 1];
if (!out) { console.error("--out needs a path"); Deno.exit(2); }

const rows = parseCatalog(await Deno.readTextFile("scripts/catalog/catalog.json"));
const verifiedAt = new Date().toISOString();
const failures: string[] = [];
for (const row of rows) {
  const url = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${row.youtube_id}&format=json`;
  const response = await fetch(url);
  if (!response.ok) { failures.push(`${row.youtube_id}: oEmbed ${response.status}`); continue; }
  const body = await response.json() as { title: string; author_name: string };
  if (!titleMatches(row.title, body.title)) failures.push(`${row.youtube_id}: title "${body.title}" does not start with "${row.title}"`);
  if (!durationPlausible(row.title, row.duration_s)) failures.push(`${row.youtube_id}: duration ${row.duration_s}s disagrees with the title`);
  if (!channelMatches(row.channel, body.author_name)) failures.push(`${row.youtube_id}: channel is "${body.author_name}", not "${row.channel}"`);
}
if (failures.length) { console.error(failures.join("\n")); Deno.exit(1); }
await Deno.writeTextFile(out, seedSQL(rows, verifiedAt));
console.log(`verified ${rows.length} videos, wrote ${out}`);
