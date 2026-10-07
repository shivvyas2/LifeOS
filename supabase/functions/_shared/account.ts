// The account's own controls: clearing chosen data, scheduling and cancelling
// deletion, and the daily purge that carries deletions out. Handlers take
// their storage as dependencies so every path is tested without a database.
// Logs carry counts and kinds, never content.

import { json } from "./supabase.ts";

export type ServerCategory = "notes" | "health" | "messages";
const SERVER: readonly string[] = ["notes", "health", "messages"];
const LOCAL_ONLY: readonly string[] = ["habits", "money", "chats"];
const GRACE_DAYS = 30;

export type AccountStore = {
  clear(user: string, categories: ServerCategory[]): Promise<void>;
  /// Null when the account has no profile row to stamp.
  schedule(user: string, at: Date): Promise<Date | null>;
  cancel(user: string): Promise<void>;
  scheduledFor(user: string): Promise<Date | null>;
  deletedAmong(ids: string[]): Promise<string[]>;
};

export async function handleAccountData(
  req: Request,
  deps: { resolveUser: (req: Request) => Promise<string | null>; store: AccountStore; now: Date },
): Promise<Response> {
  const url = new URL(req.url);
  const asked = url.searchParams.get("deleted");
  if (req.method === "GET" && asked !== null) {
    const ids = asked.split(",").map((id) => id.trim()).filter(Boolean);
    if (ids.length === 0 || ids.length > 20) return json({ error: "invalid_ids" }, 400);
    return json({ deleted: await deps.store.deletedAmong(ids) }, 200);
  }

  const user = await deps.resolveUser(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  switch (req.method) {
    case "POST": {
      let body: { clear?: unknown };
      try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }
      if (!Array.isArray(body.clear)) return json({ error: "invalid_body" }, 400);
      const names = body.clear.map(String);
      if (names.some((n) => !SERVER.includes(n) && !LOCAL_ONLY.includes(n))) {
        return json({ error: "unknown_category" }, 400);
      }
      const server = names.filter((n) => SERVER.includes(n)) as ServerCategory[];
      if (server.length) await deps.store.clear(user, server);
      return json({ cleared: server }, 200);
    }
    case "DELETE": {
      const at = new Date(deps.now.getTime() + GRACE_DAYS * 86_400_000);
      const date = await deps.store.schedule(user, at);
      // Nothing to stamp means nothing would ever be deleted: say so rather
      // than let the phone sign out believing it was scheduled.
      if (!date) return json({ error: "no_profile" }, 409);
      return json({ deletion_scheduled_for: date.toISOString() }, 200);
    }
    case "PATCH": {
      let body: { keep?: unknown };
      try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }
      if (body.keep !== true) return json({ error: "invalid_body" }, 400);
      await deps.store.cancel(user);
      return json({ deletion_scheduled_for: null }, 200);
    }
    case "GET": {
      const date = await deps.store.scheduledFor(user);
      return json({ deletion_scheduled_for: date ? date.toISOString() : null }, 200);
    }
    default:
      return json({ error: "method_not_allowed" }, 405);
  }
}

export type PurgeDeps = {
  due(now: Date): Promise<string[]>;
  /// Read again just before anything irreversible: an account kept after
  /// the run took its list must be left alone.
  stillDue(user: string, now: Date): Promise<boolean>;
  ownedGroups(user: string): Promise<string[]>;
  heirOf(group: string, user: string): Promise<string | null>;
  transfer(group: string, heir: string): Promise<void>;
  deleteGroup(group: string): Promise<void>;
  /// Shared projects go the same way as groups: the owner column cascades,
  /// so ownership passes on before the login goes.
  ownedProjects(user: string): Promise<string[]>;
  projectHeirOf(project: string, user: string): Promise<string | null>;
  transferProject(project: string, heir: string): Promise<void>;
  deleteProject(project: string): Promise<void>;
  revokeConnections(user: string): Promise<void>;
  removeAvatars(user: string): Promise<void>;
  deleteUser(user: string): Promise<void>;
  recordDeleted(user: string): Promise<void>;
  log(line: string): void;
};

/// Each due account in turn: groups first (the owner column cascades), then
/// the connections, the photos, the login, and the record.
export async function runPurge(deps: PurgeDeps, now: Date): Promise<{ deleted: number; failed: number }> {
  let deleted = 0, failed = 0;
  for (const user of await deps.due(now)) {
    try {
      if (!(await deps.stillDue(user, now))) continue;
      for (const group of await deps.ownedGroups(user)) {
        const heir = await deps.heirOf(group, user);
        if (heir) await deps.transfer(group, heir); else await deps.deleteGroup(group);
      }
      for (const project of await deps.ownedProjects(user)) {
        const heir = await deps.projectHeirOf(project, user);
        if (heir) await deps.transferProject(project, heir); else await deps.deleteProject(project);
      }
      await deps.revokeConnections(user);
      await deps.removeAvatars(user);
      await deps.deleteUser(user);
      await deps.recordDeleted(user);
      deleted += 1;
    } catch (error) {
      failed += 1;
      deps.log(`purge failed: ${error instanceof Error ? error.message : "unknown"}`);
    }
  }
  deps.log(`purge done: ${deleted} deleted, ${failed} failed`);
  return { deleted, failed };
}

export async function handleAccountPurge(
  req: Request,
  deps: { secret: string; run: () => Promise<{ deleted: number; failed: number }> },
): Promise<Response> {
  const given = req.headers.get("x-purge-secret") ?? "";
  if (!deps.secret || given !== deps.secret) return json({ error: "unauthorized" }, 401);
  return json(await deps.run(), 200);
}
