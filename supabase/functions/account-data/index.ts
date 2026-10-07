import { resolveUser, serviceClient } from "../_shared/supabase.ts";
import { type AccountStore, handleAccountData, type ServerCategory } from "../_shared/account.ts";

const TABLES: Record<ServerCategory, string[]> = {
  notes: ["note_documents", "note_folders"],
  // Older server copies of health data; the privacy plan may already have
  // dropped some, so a missing table is not a failure.
  health: ["daily_metrics", "sleep_records", "workout_records", "whoop_raw"],
  messages: [],
};
const UNDEFINED_TABLE = "42P01";

function store(): AccountStore {
  const db = serviceClient();
  return {
    async clear(user, categories) {
      for (const category of categories) {
        for (const table of TABLES[category]) {
          const { error } = await db.from(table).delete().eq("user_id", user);
          if (error && error.code !== UNDEFINED_TABLE) throw new Error(`clear_${table}`);
        }
        if (category === "messages") {
          const direct = await db.from("messages").delete().or(`sender.eq.${user},recipient.eq.${user}`);
          if (direct.error) throw new Error("clear_messages");
          const group = await db.from("group_messages").delete().eq("sender", user);
          if (group.error) throw new Error("clear_group_messages");
        }
      }
    },
    async schedule(user, at) {
      const { data, error: readError } = await db.from("profiles").select("deletion_scheduled_for")
        .eq("user_id", user).maybeSingle();
      // A failed read must not fall through and move an existing date.
      if (readError) throw new Error("schedule_read_failed");
      if (!data) return null;
      if (data.deletion_scheduled_for) return new Date(data.deletion_scheduled_for);
      const { data: updated, error } = await db.from("profiles")
        .update({ deletion_scheduled_for: at.toISOString() }).eq("user_id", user).select("user_id");
      if (error) throw new Error("schedule_failed");
      return updated && updated.length > 0 ? at : null;
    },
    async cancel(user) {
      const { error } = await db.from("profiles").update({ deletion_scheduled_for: null }).eq("user_id", user);
      if (error) throw new Error("cancel_failed");
    },
    async scheduledFor(user) {
      const { data } = await db.from("profiles").select("deletion_scheduled_for").eq("user_id", user).maybeSingle();
      return data?.deletion_scheduled_for ? new Date(data.deletion_scheduled_for) : null;
    },
    async deletedAmong(ids) {
      const { data } = await db.from("deleted_accounts").select("user_id").in("user_id", ids);
      return (data ?? []).map((row: { user_id: string }) => row.user_id);
    },
  };
}

Deno.serve(async (req) => {
  try {
    return await handleAccountData(req, { resolveUser, store: store(), now: new Date() });
  } catch (error) {
    console.error(`account-data failed: ${error instanceof Error ? error.message : "unknown"}`);
    return new Response(JSON.stringify({ error: "storage_failed" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
