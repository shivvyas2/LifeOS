export const GOALS = ["strength", "hypertrophy", "endurance", "mobility"] as const;
export const SPLITS = ["push", "pull", "legs", "upper", "lower", "full", "core", "arms", "chest", "back", "shoulders", "mobility", "cardio"] as const;
export const EQUIPMENT = ["none", "dumbbells", "barbell", "bands", "machine", "kettlebell"] as const;

export interface CatalogRow {
  youtube_id: string; title: string; channel: string; duration_s: number;
  goal: string[]; split: string; muscles: string[]; equipment: string[]; intensity: number;
  source_url?: string;
}

const ID = /^[A-Za-z0-9_-]{11}$/;

export function parseCatalog(json: string): CatalogRow[] {
  const rows = JSON.parse(json) as CatalogRow[];
  for (const row of rows) {
    if (!ID.test(row.youtube_id)) throw new Error(`bad id ${row.youtube_id}`);
    if (!row.goal.length || row.goal.some((g) => !(GOALS as readonly string[]).includes(g))) throw new Error(`bad goal in ${row.youtube_id}`);
    if (!(SPLITS as readonly string[]).includes(row.split)) throw new Error(`bad split in ${row.youtube_id}`);
    if (row.equipment.some((e) => !(EQUIPMENT as readonly string[]).includes(e))) throw new Error(`bad equipment in ${row.youtube_id}`);
    if (!Number.isInteger(row.intensity) || row.intensity < 1 || row.intensity > 3) throw new Error(`bad intensity in ${row.youtube_id}`);
    if (!Number.isInteger(row.duration_s) || row.duration_s <= 0) throw new Error(`bad duration in ${row.youtube_id}`);
  }
  const ids = new Set(rows.map((r) => r.youtube_id));
  if (ids.size !== rows.length) throw new Error("duplicate id");
  return rows;
}

const normalise = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

export function titleMatches(rowTitle: string, oembedTitle: string): boolean {
  return normalise(oembedTitle).startsWith(normalise(rowTitle));
}

export function durationPlausible(title: string, durationS: number): boolean {
  const stated = /(\d+)\s*min/i.exec(title);
  if (!stated) return true;
  const seconds = Number(stated[1]) * 60;
  return Math.abs(durationS - seconds) <= seconds * 0.1;
}

const quote = (s: string) => `'${s.replace(/'/g, "''")}'`;
const array = (items: string[]) => items.length ? `array[${items.map(quote).join(",")}]` : "'{}'";

export function rowToSQL(row: CatalogRow, verifiedAt: string): string {
  return `insert into public.workout_videos (youtube_id, title, channel, duration_s, goal, split, muscles, equipment, intensity, verified_at) values (` +
    `${quote(row.youtube_id)}, ${quote(row.title)}, ${quote(row.channel)}, ${row.duration_s}, ${array(row.goal)}, ${quote(row.split)}, ` +
    `${array(row.muscles)}, ${array(row.equipment)}, ${row.intensity}, ${quote(verifiedAt)}) on conflict (youtube_id) do update set ` +
    `title = excluded.title, channel = excluded.channel, duration_s = excluded.duration_s, goal = excluded.goal, split = excluded.split, ` +
    `muscles = excluded.muscles, equipment = excluded.equipment, intensity = excluded.intensity, verified_at = excluded.verified_at, updated_at = now();`;
}
