import { assertEquals } from "jsr:@std/assert@1";
import { mintSession } from "./otp_twilio.ts";

// GoTrue stores auth.users.phone without the leading "+" (it strips it on
// create). A returning user therefore only resolves if the lookup RPC is
// queried in that stored format; querying with "+1..." misses, the function
// falls into the create branch, and GoTrue rejects the duplicate. This fake
// backend reproduces those semantics.
function fakeBackend(calls: string[]): typeof fetch {
  return async (input: URL | RequestInfo, init?: RequestInit) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(String(init.body)) : {};

    if (url.endsWith("/rest/v1/rpc/otp_user_id_for_phone")) {
      calls.push("lookup");
      const found = body.p_phone === "11234567890";
      return Response.json(found ? "00000000-0000-0000-0000-000000000001" : null);
    }
    if (url.includes("/auth/v1/admin/users/")) {
      calls.push("update");
      return Response.json({});
    }
    if (url.endsWith("/auth/v1/admin/users")) {
      calls.push("create");
      return Response.json({ error_code: "email_exists" }, { status: 422 });
    }
    if (url.endsWith("/auth/v1/admin/generate_link")) {
      calls.push("link");
      return Response.json({ properties: { hashed_token: "hash" } });
    }
    if (url.endsWith("/auth/v1/verify")) {
      calls.push("verify");
      return Response.json({ access_token: "at", refresh_token: "rt" });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };
}

Deno.test("a returning user's phone is found in GoTrue's stored format", async () => {
  const calls: string[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = fakeBackend(calls);
  try {
    const response = await mintSession({
      supabaseURL: "https://x.supabase.co",
      serviceKey: "service",
      anonKey: "anon",
      phone: "+11234567890",
    });
    assertEquals(response.status, 200);
    assertEquals(calls.includes("create"), false);
    assertEquals(calls.includes("update"), true);
  } finally {
    globalThis.fetch = realFetch;
  }
});
