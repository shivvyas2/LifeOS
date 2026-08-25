const encoder = new TextEncoder();

export const TEST_PHONE = "+11234567890";
export const TEST_CODE = "123123";

export type GuardDecision =
  | { ok: true; phone: string; prefix: string }
  | { ok: false; error: string; status: number };

export function normalizePhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 8 || digits.length > 15) return null;
  return `+${digits}`;
}

export function isAcceptable(e164: string): boolean {
  if (!e164.startsWith("+")) return false;
  const digits = e164.slice(1);
  if (!/^\d+$/.test(digits)) return false;
  if (digits.startsWith("91")) {
    const national = digits.slice(2);
    return national.length === 10 && /^[6-9]/.test(national);
  }
  if (digits.startsWith("1")) {
    return digits.length === 11;
  }
  return false;
}

export function pumpingPrefix(e164: string): string {
  const digits = e164.slice(1);
  if (digits.startsWith("91") && digits.length >= 6) return digits.slice(0, 6);
  return digits.slice(0, Math.min(5, digits.length));
}

export function clientIP(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for") ?? req.headers.get("x-real-ip") ?? "";
  const first = forwarded.split(",")[0]?.trim();
  return first && first.length > 0 ? first : "unknown";
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function hashIdentity(value: string, pepper: string): Promise<string> {
  return sha256(`${pepper}:${value}`);
}

export function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function restHeaders(serviceKey: string): HeadersInit {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

export async function eventCount(
  restURL: string,
  serviceKey: string,
  column: "phone_hash" | "prefix" | "ip_hash",
  value: string,
  kind: string,
  sinceISO: string,
): Promise<number> {
  const params = new URLSearchParams({
    select: "id",
    [column]: `eq.${value}`,
    kind: `eq.${kind}`,
    created_at: `gte.${sinceISO}`,
  });
  const response = await fetch(`${restURL}/otp_events?${params}`, {
    headers: {
      ...restHeaders(serviceKey),
      Prefer: "count=exact",
      Range: "0-0",
    },
  });
  if (!response.ok) throw new Error("otp_events_unavailable");
  const range = response.headers.get("content-range") ?? "*/0";
  const total = range.split("/")[1];
  return Number.parseInt(total ?? "0", 10) || 0;
}

export async function recordEvent(
  restURL: string,
  serviceKey: string,
  event: { phone_hash: string; prefix: string; ip_hash: string; kind: string },
): Promise<void> {
  await fetch(`${restURL}/otp_events`, {
    method: "POST",
    headers: { ...restHeaders(serviceKey), Prefer: "return=minimal" },
    body: JSON.stringify(event),
  });
}

export async function allowStart(args: {
  restURL: string;
  serviceKey: string;
  phoneHash: string;
  prefix: string;
  ipHash: string;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const now = Date.now();
  const hourAgo = new Date(now - 60 * 60 * 1000).toISOString();
  const dayAgo = new Date(now - 24 * 60 * 60 * 1000).toISOString();
  const cooldown = new Date(now - 45 * 1000).toISOString();

  const recentPhone = await eventCount(args.restURL, args.serviceKey, "phone_hash", args.phoneHash, "start", cooldown);
  if (recentPhone > 0) return { ok: false, error: "rate_phone" };

  const hourPhone = await eventCount(args.restURL, args.serviceKey, "phone_hash", args.phoneHash, "start", hourAgo);
  if (hourPhone >= 5) return { ok: false, error: "rate_phone" };

  const dayPhone = await eventCount(args.restURL, args.serviceKey, "phone_hash", args.phoneHash, "start", dayAgo);
  if (dayPhone >= 10) return { ok: false, error: "rate_phone" };

  const hourIP = await eventCount(args.restURL, args.serviceKey, "ip_hash", args.ipHash, "start", hourAgo);
  if (hourIP >= 10) return { ok: false, error: "rate_ip" };

  const dayIP = await eventCount(args.restURL, args.serviceKey, "ip_hash", args.ipHash, "start", dayAgo);
  if (dayIP >= 25) return { ok: false, error: "rate_ip" };

  const hourPrefix = await eventCount(args.restURL, args.serviceKey, "prefix", args.prefix, "start", hourAgo);
  if (hourPrefix >= 15) return { ok: false, error: "rate_prefix" };

  return { ok: true };
}

export async function allowCheck(args: {
  restURL: string;
  serviceKey: string;
  phoneHash: string;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const windowStart = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const fails = await eventCount(
    args.restURL,
    args.serviceKey,
    "phone_hash",
    args.phoneHash,
    "check_fail",
    windowStart,
  );
  if (fails >= 5) return { ok: false, error: "rate_check" };
  return { ok: true };
}

export function parsePhone(raw: unknown): GuardDecision {
  const phone = normalizePhone(raw);
  if (!phone || !isAcceptable(phone)) {
    return { ok: false, error: "invalid_phone", status: 400 };
  }
  return { ok: true, phone, prefix: pumpingPrefix(phone) };
}
