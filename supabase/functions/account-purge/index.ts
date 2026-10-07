// The daily purge, called only by the pg_cron job with PURGE_SECRET.
import { serviceClient } from "../_shared/supabase.ts";
import { callPlaid, PlaidError } from "../_shared/plaid.ts";
import { handleAccountPurge, type PurgeDeps, runPurge } from "../_shared/account.ts";

function deps(): PurgeDeps {
  const db = serviceClient();
  return {
    async due(now) {
      const { data, error } = await db.from("profiles").select("user_id")
        .lte("deletion_scheduled_for", now.toISOString());
      if (error) throw new Error("due_failed");
      return (data ?? []).map((row: { user_id: string }) => row.user_id);
    },
    async stillDue(user, now) {
      const { data, error } = await db.from("profiles").select("deletion_scheduled_for")
        .eq("user_id", user).maybeSingle();
      if (error) throw new Error("recheck_failed");
      return !!data?.deletion_scheduled_for && new Date(data.deletion_scheduled_for) <= now;
    },
    async ownedGroups(user) {
      const { data, error } = await db.from("social_groups").select("id").eq("owner_id", user);
      if (error) throw new Error("groups_failed");
      return (data ?? []).map((row: { id: string }) => row.id);
    },
    async heirOf(group, user) {
      const { data, error } = await db.from("group_members").select("user_id")
        .eq("group_id", group).eq("status", "accepted").neq("user_id", user)
        .order("joined_at", { ascending: true }).limit(1).maybeSingle();
      if (error) throw new Error("heir_failed");
      return data?.user_id ?? null;
    },
    async transfer(group, heir) {
      const { error } = await db.from("social_groups").update({ owner_id: heir }).eq("id", group);
      if (error) throw new Error("transfer_failed");
    },
    async deleteGroup(group) {
      const { error } = await db.from("social_groups").delete().eq("id", group);
      if (error) throw new Error("delete_group_failed");
    },
    async ownedProjects(user) {
      const { data, error } = await db.from("projects").select("id").eq("owner_id", user);
      if (error) throw new Error("projects_failed");
      return (data ?? []).map((row: { id: string }) => row.id);
    },
    async projectHeirOf(project, user) {
      const { data, error } = await db.from("project_members").select("user_id")
        .eq("project_id", project).neq("user_id", user)
        .order("added_at", { ascending: true }).limit(1).maybeSingle();
      if (error) throw new Error("project_heir_failed");
      return data?.user_id ?? null;
    },
    async transferProject(project, heir) {
      const owner = await db.from("projects").update({ owner_id: heir }).eq("id", project);
      if (owner.error) throw new Error("transfer_project_failed");
      const role = await db.from("project_members").update({ role: "owner" })
        .eq("project_id", project).eq("user_id", heir);
      if (role.error) throw new Error("transfer_project_role_failed");
    },
    async deleteProject(project) {
      // A tombstone, so members' phones learn it is gone on their next pull.
      const { error } = await db.from("projects").update({ deleted_at: new Date().toISOString() }).eq("id", project);
      if (error) throw new Error("delete_project_failed");
    },
    async revokeConnections(user) {
      // Plaid keeps billing for an Item that still exists, so removal there is
      // required; an Item Plaid no longer knows is already gone.
      // A failed read must stop this account: deleting the login would drop
      // the rows while the Items stay live at Plaid, with nothing to retry from.
      const { data: items, error: itemsError } = await db.from("plaid_items").select("access_token").eq("user_id", user);
      if (itemsError) throw new Error("plaid_items_failed");
      for (const item of items ?? []) {
        try {
          await callPlaid("/item/remove", { access_token: item.access_token });
        } catch (error) {
          if (!(error instanceof PlaidError && error.code === "ITEM_NOT_FOUND")) throw error;
        }
      }
      // Whoop and Fitbit revokes are best effort: their rows go with the login.
      const { data: whoop } = await db.from("whoop_connections").select("access_token").eq("user_id", user).maybeSingle();
      if (whoop?.access_token) {
        const res = await fetch("https://api.prod.whoop.com/developer/v2/user/access", {
          method: "DELETE", headers: { Authorization: `Bearer ${whoop.access_token}` },
        }).catch(() => null);
        if (!res?.ok) console.log(`whoop revoke: ${res?.status ?? "unreachable"}`);
      }
      const { data: fitbit } = await db.from("fitbit_connections").select("access_token").eq("user_id", user).maybeSingle();
      const id = Deno.env.get("FITBIT_CLIENT_ID"), secret = Deno.env.get("FITBIT_CLIENT_SECRET");
      if (fitbit?.access_token && id && secret) {
        const res = await fetch("https://api.fitbit.com/oauth2/revoke", {
          method: "POST",
          headers: { Authorization: `Basic ${btoa(`${id}:${secret}`)}`, "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ token: fitbit.access_token }).toString(),
        }).catch(() => null);
        if (!res?.ok) console.log(`fitbit revoke: ${res?.status ?? "unreachable"}`);
      }
    },
    async removeAvatars(user) {
      const { data } = await db.storage.from("avatars").list(user);
      const paths = (data ?? []).map((file: { name: string }) => `${user}/${file.name}`);
      if (paths.length) {
        const { error } = await db.storage.from("avatars").remove(paths);
        if (error) throw new Error("avatars_failed");
      }
    },
    async deleteUser(user) {
      const { error } = await db.auth.admin.deleteUser(user);
      if (error) throw new Error("delete_user_failed");
    },
    async recordDeleted(user) {
      const { error } = await db.from("deleted_accounts").upsert({ user_id: user });
      if (error) throw new Error("record_failed");
    },
    log: (line) => console.log(line),
  };
}

Deno.serve((req) =>
  handleAccountPurge(req, {
    secret: Deno.env.get("PURGE_SECRET") ?? "",
    run: () => runPurge(deps(), new Date()),
  })
);
