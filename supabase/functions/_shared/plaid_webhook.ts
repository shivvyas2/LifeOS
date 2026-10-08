// Plaid webhooks: proving one came from Plaid, and deciding what it means.
//
// The webhook endpoint is public and runs with the service-role key, because
// Plaid has no user session to send. So the signature is the whole security
// boundary: an unverified body could name any item_id and make this function
// push at that item's owner. Every request is verified before its body is
// even parsed.
//
// Plaid signs each webhook with an ES256 JWT in the `Plaid-Verification`
// header. The JWT's claims carry a SHA-256 of the exact body bytes and the
// time it was issued; its key is fetched from Plaid by `kid`.
//
// The decisions are pure and tested. `verifyPlaidWebhook` takes the key
// fetcher as an argument so the test can sign with its own key.

/// Plaid's documented replay window.
export const MAX_AGE_SECONDS = 5 * 60;

export interface PlaidJWK {
  alg: string;
  crv: string;
  kid: string;
  kty: string;
  x: string;
  y: string;
  /// Non-null once Plaid has rotated the key out.
  expired_at?: number | null;
}

export type VerifyFailure =
  | "missing_header"
  | "malformed_token"
  | "wrong_algorithm"
  | "unknown_key"
  | "expired_key"
  | "bad_signature"
  | "stale"
  | "body_mismatch";

export type VerifyResult = { ok: true } | { ok: false; reason: VerifyFailure };

/// What a webhook asks the app to do.
///
/// Only one thing: sync. New or changed transactions obviously; an item error
/// or a repaired login too, because the sync is what raises or clears the
/// reconnect banner on the phone. Everything else Plaid sends is ignored, so a
/// new webhook type Plaid adds tomorrow does not wake anybody's phone.
export function webhookAction(body: Record<string, unknown>): "sync" | null {
  const type = body.webhook_type;
  const code = body.webhook_code;
  if (type === "TRANSACTIONS" && code === "SYNC_UPDATES_AVAILABLE") return "sync";
  if (type === "ITEM" && (code === "ERROR" || code === "LOGIN_REPAIRED" || code === "PENDING_EXPIRATION")) {
    return "sync";
  }
  return null;
}

/// The silent push that wakes the app to sync. No alert, no sound, no badge:
/// the transaction itself is the news, and it is on the Money tab the next
/// time anyone looks. Nothing about the transaction is in it; the phone asks
/// Plaid itself, through plaid-sync, as it always has.
export function silentSyncPayload(): Record<string, unknown> {
  return { aps: { "content-available": 1 }, kind: "plaid-sync" };
}

export function base64urlDecode(text: string): Uint8Array<ArrayBuffer> {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(text.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/// Equal in time regardless of where the strings first differ.
export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}

export async function sha256Hex(body: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  return hex(new Uint8Array(digest));
}

export async function verifyPlaidWebhook(
  rawBody: string,
  header: string | null,
  now: Date,
  fetchKey: (kid: string) => Promise<PlaidJWK | null>,
): Promise<VerifyResult> {
  if (!header) return { ok: false, reason: "missing_header" };
  const parts = header.split(".");
  if (parts.length !== 3) return { ok: false, reason: "malformed_token" };

  let jwtHeader: { alg?: string; kid?: string };
  let claims: { iat?: number; request_body_sha256?: string };
  try {
    jwtHeader = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[1])));
  } catch {
    return { ok: false, reason: "malformed_token" };
  }
  // Checked before any key is fetched: "none" or an HMAC algorithm here is
  // the classic way to forge a JWT.
  if (jwtHeader.alg !== "ES256") return { ok: false, reason: "wrong_algorithm" };
  if (!jwtHeader.kid) return { ok: false, reason: "malformed_token" };

  const jwk = await fetchKey(jwtHeader.kid);
  if (!jwk) return { ok: false, reason: "unknown_key" };
  if (jwk.expired_at) return { ok: false, reason: "expired_key" };

  let valid = false;
  try {
    const key = await crypto.subtle.importKey(
      "jwk",
      { kty: jwk.kty, crv: jwk.crv, x: jwk.x, y: jwk.y },
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      base64urlDecode(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    valid = false;
  }
  if (!valid) return { ok: false, reason: "bad_signature" };

  const age = Math.floor(now.getTime() / 1000) - (claims.iat ?? 0);
  if (typeof claims.iat !== "number" || age > MAX_AGE_SECONDS || age < -MAX_AGE_SECONDS) {
    return { ok: false, reason: "stale" };
  }

  const expected = claims.request_body_sha256 ?? "";
  if (!constantTimeEqual(await sha256Hex(rawBody), expected)) return { ok: false, reason: "body_mismatch" };

  return { ok: true };
}
