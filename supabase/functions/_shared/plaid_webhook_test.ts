import { assertEquals } from "jsr:@std/assert@1";
import { base64url, pushHeaders } from "./apns.ts";
import {
  constantTimeEqual,
  type PlaidJWK,
  sha256Hex,
  silentSyncPayload,
  verifyPlaidWebhook,
  webhookAction,
} from "./plaid_webhook.ts";

const encoder = new TextEncoder();
const NOW = new Date("2026-10-08T12:00:00Z");
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);
const BODY = JSON.stringify({ webhook_type: "TRANSACTIONS", webhook_code: "SYNC_UPDATES_AVAILABLE", item_id: "item-1" });

async function keyPair() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  const plaid: PlaidJWK = { alg: "ES256", crv: "P-256", kid: "k1", kty: "EC", x: jwk.x!, y: jwk.y!, expired_at: null };
  return { privateKey: pair.privateKey, plaid };
}

async function sign(
  privateKey: CryptoKey,
  claims: Record<string, unknown>,
  header: Record<string, unknown> = { alg: "ES256", kid: "k1", typ: "JWT" },
): Promise<string> {
  const head = base64url(encoder.encode(JSON.stringify(header)));
  const body = base64url(encoder.encode(JSON.stringify(claims)));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, encoder.encode(`${head}.${body}`));
  return `${head}.${body}.${base64url(new Uint8Array(signature))}`;
}

Deno.test("a genuine webhook verifies", async () => {
  const { privateKey, plaid } = await keyPair();
  const token = await sign(privateKey, { iat: NOW_SECONDS - 10, request_body_sha256: await sha256Hex(BODY) });
  assertEquals(await verifyPlaidWebhook(BODY, token, NOW, async () => plaid), { ok: true });
});

Deno.test("a body changed after signing is rejected", async () => {
  const { privateKey, plaid } = await keyPair();
  const token = await sign(privateKey, { iat: NOW_SECONDS, request_body_sha256: await sha256Hex(BODY) });
  const forged = BODY.replace("item-1", "item-2");
  assertEquals(await verifyPlaidWebhook(forged, token, NOW, async () => plaid), { ok: false, reason: "body_mismatch" });
});

Deno.test("a token signed by someone else's key is rejected", async () => {
  const { plaid } = await keyPair();
  const attacker = await keyPair();
  const token = await sign(attacker.privateKey, { iat: NOW_SECONDS, request_body_sha256: await sha256Hex(BODY) });
  assertEquals(await verifyPlaidWebhook(BODY, token, NOW, async () => plaid), { ok: false, reason: "bad_signature" });
});

Deno.test("an old token is a replay", async () => {
  const { privateKey, plaid } = await keyPair();
  const token = await sign(privateKey, { iat: NOW_SECONDS - 6 * 60, request_body_sha256: await sha256Hex(BODY) });
  assertEquals(await verifyPlaidWebhook(BODY, token, NOW, async () => plaid), { ok: false, reason: "stale" });
});

Deno.test("alg none never reaches a key lookup", async () => {
  let fetched = false;
  const { privateKey } = await keyPair();
  const token = await sign(privateKey, { iat: NOW_SECONDS }, { alg: "none", kid: "k1" });
  const result = await verifyPlaidWebhook(BODY, token, NOW, async () => {
    fetched = true;
    return null;
  });
  assertEquals(result, { ok: false, reason: "wrong_algorithm" });
  assertEquals(fetched, false);
});

Deno.test("missing, malformed, unknown and rotated keys are all refused", async () => {
  const { privateKey, plaid } = await keyPair();
  const token = await sign(privateKey, { iat: NOW_SECONDS, request_body_sha256: await sha256Hex(BODY) });
  assertEquals(await verifyPlaidWebhook(BODY, null, NOW, async () => plaid), { ok: false, reason: "missing_header" });
  assertEquals(await verifyPlaidWebhook(BODY, "a.b", NOW, async () => plaid), { ok: false, reason: "malformed_token" });
  assertEquals(await verifyPlaidWebhook(BODY, token, NOW, async () => null), { ok: false, reason: "unknown_key" });
  assertEquals(
    await verifyPlaidWebhook(BODY, token, NOW, async () => ({ ...plaid, expired_at: NOW_SECONDS })),
    { ok: false, reason: "expired_key" },
  );
});

Deno.test("only sync-worthy webhooks wake a phone", () => {
  assertEquals(webhookAction({ webhook_type: "TRANSACTIONS", webhook_code: "SYNC_UPDATES_AVAILABLE" }), "sync");
  assertEquals(webhookAction({ webhook_type: "ITEM", webhook_code: "ERROR" }), "sync");
  assertEquals(webhookAction({ webhook_type: "ITEM", webhook_code: "LOGIN_REPAIRED" }), "sync");
  assertEquals(webhookAction({ webhook_type: "TRANSACTIONS", webhook_code: "DEFAULT_UPDATE" }), null);
  assertEquals(webhookAction({ webhook_type: "AUTH", webhook_code: "AUTOMATICALLY_VERIFIED" }), null);
});

Deno.test("the wake-up is silent and carries nothing about money", () => {
  assertEquals(silentSyncPayload(), { aps: { "content-available": 1 }, kind: "plaid-sync" });
});

Deno.test("background pushes use the type and priority Apple requires", () => {
  const headers = pushHeaders("t", "com.example", NOW, "background");
  assertEquals(headers["apns-push-type"], "background");
  assertEquals(headers["apns-priority"], "5");
  assertEquals(pushHeaders("t", "com.example", NOW)["apns-push-type"], "alert");
});

Deno.test("constant-time compare still compares", () => {
  assertEquals(constantTimeEqual("abc", "abc"), true);
  assertEquals(constantTimeEqual("abc", "abd"), false);
  assertEquals(constantTimeEqual("abc", "ab"), false);
});
