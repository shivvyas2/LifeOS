import { assertEquals } from "jsr:@std/assert@1";
import { handleGitHubToken } from "./github.ts";

const env = (values: Record<string, string>) => (name: string) => values[name];
const configured = env({ GITHUB_CLIENT_ID: "id", GITHUB_CLIENT_SECRET: "secret" });
const signedIn = () => Promise.resolve("user-1");

function post(body: unknown, auth = true): Request {
  return new Request("http://x/github-token", {
    method: "POST",
    headers: auth ? { Authorization: "Bearer jwt", "Content-Type": "application/json" } : {},
    body: JSON.stringify(body),
  });
}

Deno.test("no session, no exchange", async () => {
  const res = await handleGitHubToken(post({ code: "c" }, false), {
    resolveUser: () => Promise.resolve(null), fetch: () => { throw new Error("must not call"); }, env: configured,
  });
  assertEquals(res.status, 401);
});

Deno.test("without configuration it says so", async () => {
  const res = await handleGitHubToken(post({ code: "c", verifier: "v", redirect_uri: "almanac://github-callback" }), {
    resolveUser: signedIn, fetch: () => { throw new Error("must not call"); }, env: env({}),
  });
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "server_not_configured");
});

Deno.test("a good code becomes a token, and nothing else is returned", async () => {
  let sent = "";
  const res = await handleGitHubToken(post({ code: "c", verifier: "v", redirect_uri: "almanac://github-callback" }), {
    resolveUser: signedIn,
    fetch: async (_url, init) => {
      sent = String(init?.body);
      return new Response(JSON.stringify({ access_token: "gho_x", scope: "read:user,repo", token_type: "bearer" }));
    },
    env: configured,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { access_token: "gho_x", scope: "read:user,repo" });
  assertEquals(sent.includes("code_verifier=v"), true);
  assertEquals(sent.includes("client_secret=secret"), true);
});

Deno.test("GitHub's refusal comes back as 400 with its code", async () => {
  const res = await handleGitHubToken(post({ code: "bad", verifier: "v", redirect_uri: "almanac://github-callback" }), {
    resolveUser: signedIn,
    fetch: () => Promise.resolve(new Response(JSON.stringify({ error: "bad_verification_code" }))),
    env: configured,
  });
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "bad_verification_code");
});

Deno.test("DELETE revokes the grant, and an unknown token still counts as done", async () => {
  let called = "";
  const del = new Request("http://x/github-token", {
    method: "DELETE", headers: { Authorization: "Bearer jwt" }, body: JSON.stringify({ access_token: "gho_x" }),
  });
  const res = await handleGitHubToken(del, {
    resolveUser: signedIn,
    fetch: (url, init) => {
      called = `${init?.method} ${url}`;
      return Promise.resolve(new Response(null, { status: 404 }));
    },
    env: configured,
  });
  assertEquals(res.status, 204);
  assertEquals(called, "DELETE https://api.github.com/applications/id/grant");
});
