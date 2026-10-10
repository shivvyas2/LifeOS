import { assertEquals } from "jsr:@std/assert@1";
import { handleHandoff } from "./handoff.ts";

const env = { supabaseURL: "https://x.supabase.co", serviceKey: "svc", anonKey: "anon" };

Deno.test("refuses a request with no user", async () => {
  const res = await handleHandoff(new Request("https://f/", { method: "POST" }), {
    ...env,
    resolveEmail: () => Promise.resolve(null),
    mint: () => Promise.resolve(new Response("{}")),
  });
  assertEquals(res.status, 401);
});

Deno.test("mints a session for the caller's own email", async () => {
  let minted = "";
  const res = await handleHandoff(
    new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer t" } }),
    {
      ...env,
      resolveEmail: () => Promise.resolve("s@example.com"),
      mint: (email) => {
        minted = email;
        return Promise.resolve(new Response('{"access_token":"new"}'));
      },
    },
  );
  assertEquals(res.status, 200);
  assertEquals(minted, "s@example.com");
});

Deno.test("rejects anything but POST", async () => {
  const res = await handleHandoff(new Request("https://f/", { method: "GET" }), {
    ...env,
    resolveEmail: () => Promise.resolve("s@example.com"),
    mint: () => Promise.resolve(new Response("{}")),
  });
  assertEquals(res.status, 405);
});
