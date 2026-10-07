import { assertEquals } from "jsr:@std/assert@1";
import { type AccountStore, handleAccountData, handleAccountPurge, type PurgeDeps, runPurge } from "./account.ts";

function fakeStore() {
  const calls: string[] = [];
  let scheduled: Date | null = null;
  const store: AccountStore = {
    clear: (u, c) => { calls.push(`clear ${u} ${c.join(",")}`); return Promise.resolve(); },
    schedule: (u, at) => { scheduled ??= at; calls.push(`schedule ${u}`); return Promise.resolve(scheduled); },
    cancel: (u) => { scheduled = null; calls.push(`cancel ${u}`); return Promise.resolve(); },
    scheduledFor: () => Promise.resolve(scheduled),
    deletedAmong: (ids) => Promise.resolve(ids.filter((id) => id.startsWith("gone"))),
  };
  return { store, calls };
}
const now = new Date("2026-10-07T12:00:00Z");
const signedIn = () => Promise.resolve("u1");
const req = (method: string, body?: unknown, query = "", auth = true) =>
  new Request(`http://x/account-data${query}`, {
    method, headers: auth ? { Authorization: "Bearer jwt" } : {}, body: body ? JSON.stringify(body) : undefined,
  });

Deno.test("every account call but the deleted check needs a session", async () => {
  const { store } = fakeStore();
  for (const r of [req("POST", { clear: ["notes"] }, "", false), req("DELETE", undefined, "", false), req("PATCH", { keep: true }, "", false), req("GET", undefined, "", false)]) {
    assertEquals((await handleAccountData(r, { resolveUser: () => Promise.resolve(null), store, now })).status, 401);
  }
});

Deno.test("clear deletes the caller's chosen server categories", async () => {
  const { store, calls } = fakeStore();
  const res = await handleAccountData(req("POST", { clear: ["notes", "messages", "habits"] }), { resolveUser: signedIn, store, now });
  assertEquals(res.status, 200);
  assertEquals(calls, ["clear u1 notes,messages"]);
});

Deno.test("an unknown category clears nothing", async () => {
  const { store, calls } = fakeStore();
  const res = await handleAccountData(req("POST", { clear: ["notes", "everything"] }), { resolveUser: signedIn, store, now });
  assertEquals(res.status, 400);
  assertEquals(calls, []);
});

Deno.test("deletion is scheduled thirty days out, once, and keep cancels it", async () => {
  const { store } = fakeStore();
  const first = await (await handleAccountData(req("DELETE"), { resolveUser: signedIn, store, now })).json();
  assertEquals(first.deletion_scheduled_for, "2026-11-06T12:00:00.000Z");
  const later = new Date("2026-10-10T12:00:00Z");
  const second = await (await handleAccountData(req("DELETE"), { resolveUser: signedIn, store, now: later })).json();
  assertEquals(second.deletion_scheduled_for, "2026-11-06T12:00:00.000Z");
  await handleAccountData(req("PATCH", { keep: true }), { resolveUser: signedIn, store, now });
  const status = await (await handleAccountData(req("GET"), { resolveUser: signedIn, store, now })).json();
  assertEquals(status.deletion_scheduled_for, null);
});

Deno.test("scheduling without a profile says so instead of pretending", async () => {
  const { store } = fakeStore();
  store.schedule = () => Promise.resolve(null);
  const res = await handleAccountData(req("DELETE"), { resolveUser: signedIn, store, now });
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error, "no_profile");
});

Deno.test("the deleted check is anonymous, capped, and names only deleted ids", async () => {
  const { store } = fakeStore();
  const ok = await handleAccountData(req("GET", undefined, "?deleted=gone-1,kept-2", false), { resolveUser: () => Promise.resolve(null), store, now });
  assertEquals((await ok.json()).deleted, ["gone-1"]);
  const many = Array.from({ length: 21 }, (_, i) => `gone-${i}`).join(",");
  const tooMany = await handleAccountData(req("GET", undefined, `?deleted=${many}`, false), { resolveUser: () => Promise.resolve(null), store, now });
  assertEquals(tooMany.status, 400);
});

function purgeDeps(over: Partial<PurgeDeps> = {}) {
  const steps: string[] = [];
  const deps: PurgeDeps = {
    due: () => Promise.resolve(["a", "b"]),
    stillDue: () => Promise.resolve(true),
    ownedGroups: (u) => Promise.resolve(u === "a" ? ["g-shared", "g-alone"] : []),
    heirOf: (g) => Promise.resolve(g === "g-shared" ? "c" : null),
    transfer: (g, h) => { steps.push(`transfer ${g} ${h}`); return Promise.resolve(); },
    deleteGroup: (g) => { steps.push(`delete-group ${g}`); return Promise.resolve(); },
    ownedProjects: (u) => Promise.resolve(u === "a" ? ["p-shared", "p-solo"] : []),
    projectHeirOf: (p) => Promise.resolve(p === "p-shared" ? "d" : null),
    transferProject: (p, h) => { steps.push(`transfer-project ${p} ${h}`); return Promise.resolve(); },
    deleteProject: (p) => { steps.push(`delete-project ${p}`); return Promise.resolve(); },
    revokeConnections: (u) => { steps.push(`revoke ${u}`); return Promise.resolve(); },
    removeAvatars: (u) => { steps.push(`avatars ${u}`); return Promise.resolve(); },
    deleteUser: (u) => { steps.push(`delete-user ${u}`); return Promise.resolve(); },
    recordDeleted: (u) => { steps.push(`record ${u}`); return Promise.resolve(); },
    log: () => {},
    ...over,
  };
  return { deps, steps };
}

Deno.test("groups move before the login goes", async () => {
  const { deps, steps } = purgeDeps({ due: () => Promise.resolve(["a"]) });
  const result = await runPurge(deps, now);
  assertEquals(steps, [
    "transfer g-shared c", "delete-group g-alone",
    "transfer-project p-shared d", "delete-project p-solo",
    "revoke a", "avatars a", "delete-user a", "record a",
  ]);
  assertEquals(result, { deleted: 1, failed: 0 });
});

Deno.test("one failure does not stop the run", async () => {
  const { deps, steps } = purgeDeps({
    revokeConnections: (u) => u === "a" ? Promise.reject(new Error("boom")) : Promise.resolve(),
  });
  const result = await runPurge(deps, now);
  assertEquals(result, { deleted: 1, failed: 1 });
  assertEquals(steps.includes("delete-user a"), false);
  assertEquals(steps.includes("record b"), true);
});

Deno.test("the purge answers only its secret", async () => {
  let ran = false;
  const run = () => { ran = true; return Promise.resolve({ deleted: 0, failed: 0 }); };
  const wrong = await handleAccountPurge(new Request("http://x", { method: "POST", headers: { "x-purge-secret": "nope" } }), { secret: "s3", run });
  assertEquals(wrong.status, 401);
  assertEquals(ran, false);
  const unset = await handleAccountPurge(new Request("http://x", { method: "POST", headers: { "x-purge-secret": "" } }), { secret: "", run });
  assertEquals(unset.status, 401);
  const right = await handleAccountPurge(new Request("http://x", { method: "POST", headers: { "x-purge-secret": "s3" } }), { secret: "s3", run });
  assertEquals(right.status, 200);
  assertEquals(ran, true);
});

Deno.test("an account kept after the run began is left alone", async () => {
  const { deps, steps } = purgeDeps({ stillDue: (u) => Promise.resolve(u !== "a") });
  const result = await runPurge(deps, now);
  assertEquals(result, { deleted: 1, failed: 0 });
  assertEquals(steps.some((s) => s.endsWith(" a") || s.includes("g-shared")), false);
});

