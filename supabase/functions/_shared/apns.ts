// Delivery to Apple. The decisions are pure and tested here; the two
// impure functions at the bottom are the JWT signature and the send itself,
// which are the only parts that need a key or a socket.
//
// Auth is a provider token, not a certificate: one ES256 JWT signed from a .p8
// held in the function environment, reused for under an hour. Apple rejects
// tokens minted more than once every twenty minutes or so, so minting one per
// push is not merely wasteful, it gets the sender throttled.

export const PRODUCTION_HOST = "https://api.push.apple.com";
export const SANDBOX_HOST = "https://api.sandbox.push.apple.com";

/// Apple accepts a provider token for one hour. Refreshed at fifty minutes so
/// a send never races the expiry.
export const TOKEN_TTL_SECONDS = 50 * 60;

/// How long a nudge stays worth delivering. A morning observation that arrives
/// after midnight because the phone was off is not the same message, so it is
/// allowed to expire rather than turn up stale.
export const EXPIRATION_SECONDS = 12 * 60 * 60;

/// One collapse id for the whole channel. A phone that has been off for three
/// days gets today's nudge, not three of them.
export const COLLAPSE_ID = "lifo-nudge";

export interface ApnsConfig {
  keyID: string;
  teamID: string;
  bundleID: string;
  /// The .p8 file's contents, PEM armoured, exactly as Apple hands it over.
  privateKeyPEM: string;
  /// Sandbox for development builds, production for TestFlight and the store.
  /// The wrong one returns 400 BadDeviceToken for every send, which is why
  /// this is configuration rather than a guess.
  host: string;
}

export function apnsHeader(keyID: string): Record<string, string> {
  return { alg: "ES256", kid: keyID };
}

export function apnsClaims(teamID: string, now: Date): Record<string, unknown> {
  return { iss: teamID, iat: Math.floor(now.getTime() / 1000) };
}

/// The notification itself.
///
/// `trigger` and `day` ride alongside the alert so the tap-through knows which
/// observation it is opening, and so a nudge tapped two days later can be
/// recognised as stale. The numbers are deliberately not in the payload: the
/// device re-evaluates locally rather than trusting them.
export function notificationPayload(
  body: string,
  trigger: string,
  day: string,
): Record<string, unknown> {
  return {
    aps: {
      alert: { title: "LIFO", body },
      sound: "default",
      "thread-id": COLLAPSE_ID,
    },
    trigger,
    day,
  };
}

export function pushHeaders(
  token: string,
  bundleID: string,
  now: Date,
): Record<string, string> {
  return {
    authorization: `bearer ${token}`,
    "apns-topic": bundleID,
    "apns-push-type": "alert",
    // 10 is "deliver now". A nudge is timed to a local hour, so holding it for
    // a power-saving window would defeat the point of choosing the hour.
    "apns-priority": "10",
    "apns-collapse-id": COLLAPSE_ID,
    "apns-expiration": String(Math.floor(now.getTime() / 1000) + EXPIRATION_SECONDS),
    "content-type": "application/json",
  };
}

/// Whether Apple is telling us this token is dead and the row should go.
///
/// 410 is the documented answer. 400 BadDeviceToken is the other one, and it
/// is the one that actually turns up when an app is reinstalled: without it
/// the job pushes at a dead token indefinitely.
export function isUnregistered(status: number, reason: string | null): boolean {
  if (status === 410) return true;
  return status === 400 && reason === "BadDeviceToken";
}

/// The `reason` field out of an APNs error body, or null if there is not one.
export function failureReason(body: string): string | null {
  try {
    const parsed = JSON.parse(body) as { reason?: unknown };
    return typeof parsed.reason === "string" ? parsed.reason : null;
  } catch {
    return null;
  }
}

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// The DER bytes inside a PEM block.
///
/// Tolerant of the whitespace and line endings a key picks up from being
/// pasted through a dashboard, because that is how this value actually
/// arrives. Intolerant of anything that is not a private key.
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "")
    .replace(/-----END [A-Z ]*PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  if (body.length === 0) throw new Error("apns key is not a PEM private key");
  const binary = atob(body);
  // Backed by a plain ArrayBuffer rather than whatever `Uint8Array.from`
  // infers: `crypto.subtle.importKey` takes a BufferSource, and a
  // SharedArrayBuffer-backed view does not satisfy it.
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// The two impure pieces
// ---------------------------------------------------------------------------

let cached: { token: string; mintedAt: number } | null = null;

/// A provider token, minted at most once every fifty minutes.
export async function providerToken(config: ApnsConfig, now: Date): Promise<string> {
  const seconds = Math.floor(now.getTime() / 1000);
  if (cached && seconds - cached.mintedAt < TOKEN_TTL_SECONDS) return cached.token;

  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify(apnsHeader(config.keyID))));
  const claims = base64url(encoder.encode(JSON.stringify(apnsClaims(config.teamID, now))));
  const signingInput = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKeyPEM),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto emits the raw r||s pair, which is exactly what JWS ES256 wants.
  // No DER unwrapping, and adding any would break the signature.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );

  const token = `${signingInput}.${base64url(new Uint8Array(signature))}`;
  cached = { token, mintedAt: seconds };
  return token;
}

/// Only exists so a test can prove the cache is used and reset it between
/// cases. Never called by the send path.
export function resetProviderToken(): void {
  cached = null;
}

export interface PushResult {
  status: number;
  /// True when Apple says this device token is dead and the row should go.
  unregistered: boolean;
}

export async function sendPush(
  config: ApnsConfig,
  deviceToken: string,
  payload: Record<string, unknown>,
  now: Date,
): Promise<PushResult> {
  const token = await providerToken(config, now);
  const reply = await fetch(`${config.host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: pushHeaders(token, config.bundleID, now),
    body: JSON.stringify(payload),
  });
  if (reply.ok) return { status: reply.status, unregistered: false };

  const body = await reply.text();
  const reason = failureReason(body);
  // The reason, never the token: a device token in a log line is a way to
  // push at somebody from outside this function.
  console.error(`apns send failed status=${reply.status} reason=${reason ?? "unknown"}`);
  return { status: reply.status, unregistered: isUnregistered(reply.status, reason) };
}

/// Reads the four environment values, or null when the function is not
/// configured for push. Null is not an error: a deployment without APNs keys
/// should evaluate triggers and send nothing, not crash hourly.
export function apnsConfigFromEnv(): ApnsConfig | null {
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const bundleID = Deno.env.get("APNS_BUNDLE_ID");
  const privateKeyPEM = Deno.env.get("APNS_KEY");
  if (!keyID || !teamID || !bundleID || !privateKeyPEM) return null;
  return {
    keyID,
    teamID,
    bundleID,
    privateKeyPEM,
    host: Deno.env.get("APNS_SANDBOX") === "true" ? SANDBOX_HOST : PRODUCTION_HOST,
  };
}
