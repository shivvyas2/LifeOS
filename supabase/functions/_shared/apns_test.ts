import { assertEquals, assertNotEquals, assertThrows } from "jsr:@std/assert@1";
import {
  apnsClaims,
  apnsHeader,
  base64url,
  COLLAPSE_ID,
  EXPIRATION_SECONDS,
  failureReason,
  isUnregistered,
  notificationPayload,
  pemToDer,
  providerToken,
  pushHeaders,
  resetProviderToken,
  TOKEN_TTL_SECONDS,
} from "./apns.ts";

const NOW = new Date("2026-08-28T12:00:00Z");

Deno.test("the JWT header and claims are the shape Apple documents", () => {
  assertEquals(apnsHeader("ABC123DEFG"), { alg: "ES256", kid: "ABC123DEFG" });
  assertEquals(apnsClaims("TEAM123456", NOW), {
    iss: "TEAM123456",
    iat: 1787918400,
  });
});

Deno.test("base64url drops the padding and the two unsafe characters", () => {
  // 0xFB 0xFF encodes to "+/8=" in standard base64.
  assertEquals(base64url(new Uint8Array([0xfb, 0xff])), "-_8");
  assertEquals(base64url(new Uint8Array([1])), "AQ");
});

Deno.test("a PEM key survives the whitespace a dashboard paste adds", () => {
  const der = [1, 2, 3, 4];
  const armoured = `-----BEGIN PRIVATE KEY-----\r\n${btoa("\x01\x02\x03\x04")}\r\n-----END PRIVATE KEY-----\n`;
  assertEquals(Array.from(pemToDer(armoured)), der);
  assertEquals(
    Array.from(pemToDer(`-----BEGIN EC PRIVATE KEY-----\n${btoa("\x01\x02\x03\x04")}\n-----END EC PRIVATE KEY-----`)),
    der,
  );
});

Deno.test("something that is not a key is rejected rather than sent", () => {
  assertThrows(() => pemToDer("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----"));
});

Deno.test("the payload carries the sentence and what it was about, never the numbers", () => {
  const payload = notificationPayload("Three short nights.", "short_sleep", "2026-08-28", "account-a") as {
    aps: { alert: { title: string; body: string }; "thread-id": string };
    user_id: string;
    trigger: string;
    day: string;
  };
  assertEquals(payload.aps.alert.body, "Three short nights.");
  assertEquals(payload.user_id, "account-a");
  assertEquals(payload.trigger, "short_sleep");
  assertEquals(payload.day, "2026-08-28");
  assertEquals(payload.aps["thread-id"], COLLAPSE_ID);
  // The tap-through re-evaluates locally, so shipping the figures would only
  // create a second, staler source of truth for them.
  assertEquals(JSON.stringify(payload).includes("baseline"), false);
});

Deno.test("headers collapse the channel and let a stale nudge expire", () => {
  const headers = pushHeaders("jwt", "com.shivvyas.lifeos", NOW);
  assertEquals(headers["apns-topic"], "com.shivvyas.lifeos");
  assertEquals(headers["apns-collapse-id"], COLLAPSE_ID);
  assertEquals(headers["apns-priority"], "10");
  assertEquals(
    headers["apns-expiration"],
    String(Math.floor(NOW.getTime() / 1000) + EXPIRATION_SECONDS),
  );
  assertEquals(headers.authorization, "bearer jwt");
});

Deno.test("a dead token is recognised from both answers Apple gives", () => {
  assertEquals(isUnregistered(410, "Unregistered"), true);
  // The one that actually turns up after a reinstall.
  assertEquals(isUnregistered(400, "BadDeviceToken"), true);
  // Not dead: a transient failure must never delete somebody's registration.
  assertEquals(isUnregistered(429, "TooManyRequests"), false);
  assertEquals(isUnregistered(500, null), false);
  assertEquals(isUnregistered(400, "PayloadTooLarge"), false);
});

Deno.test("a non-JSON error body yields no reason rather than throwing", () => {
  assertEquals(failureReason('{"reason":"Unregistered"}'), "Unregistered");
  assertEquals(failureReason("<html>502</html>"), null);
  assertEquals(failureReason(""), null);
});

// The one test that exercises real signing. Apple rejects a sender that mints
// a token per push, so the cache is a correctness requirement, not a saving.
Deno.test("a provider token is signed once and reused inside its window", async () => {
  resetProviderToken();
  const key = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", key.privateKey));
  let binary = "";
  for (const byte of pkcs8) binary += String.fromCharCode(byte);
  const config = {
    keyID: "ABC123DEFG",
    teamID: "TEAM123456",
    bundleID: "com.shivvyas.lifeos",
    privateKeyPEM: `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`,
    host: "https://api.push.apple.com",
  };

  const first = await providerToken(config, NOW);
  assertEquals(first.split(".").length, 3);

  // Same window: the identical token comes back rather than a fresh signature.
  const withinWindow = new Date(NOW.getTime() + (TOKEN_TTL_SECONDS - 60) * 1000);
  assertEquals(await providerToken(config, withinWindow), first);

  // Past the window: a new one.
  const pastWindow = new Date(NOW.getTime() + (TOKEN_TTL_SECONDS + 60) * 1000);
  assertNotEquals(await providerToken(config, pastWindow), first);
  resetProviderToken();
});
