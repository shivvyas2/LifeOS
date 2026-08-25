// Check a Twilio Verify code, then mint a Supabase session.
// Twilio credentials never leave this function.
import {
  TEST_CODE,
  TEST_PHONE,
  allowCheck,
  clientIP,
  hashIdentity,
  json,
  parsePhone,
  recordEvent,
} from "../_shared/otp_guard.ts";
import { mintSession, twilioCheck } from "../_shared/otp_twilio.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !serviceKey || !anonKey) {
    return json({ error: "server_not_configured" }, 500);
  }

  let body: { phone?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const parsed = parsePhone(body.phone);
  if (!parsed.ok) return json({ error: parsed.error }, parsed.status);

  const code = typeof body.code === "string" ? body.code.replace(/\D/g, "") : "";
  if (code.length < 4 || code.length > 10) return json({ error: "invalid_code" }, 400);

  const pepper = Deno.env.get("OTP_PEPPER") ?? serviceKey;
  const phoneHash = await hashIdentity(parsed.phone, pepper);
  const ipHash = await hashIdentity(clientIP(req), pepper);
  const restURL = `${supabaseURL}/rest/v1`;

  const allowed = await allowCheck({ restURL, serviceKey, phoneHash }).catch(() => null);
  if (!allowed) return json({ error: "server_not_configured" }, 500);
  if (!allowed.ok) {
    await recordEvent(restURL, serviceKey, {
      phone_hash: phoneHash,
      prefix: parsed.prefix,
      ip_hash: ipHash,
      kind: "blocked",
    });
    return json({ error: "rate_limited" }, 429);
  }

  let approved = false;
  if (parsed.phone === TEST_PHONE && code === TEST_CODE) {
    approved = true;
  } else {
    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
    const serviceSid = Deno.env.get("TWILIO_VERIFY_SERVICE_SID");
    if (!accountSid || !authToken || !serviceSid) {
      return json({ error: "server_not_configured" }, 500);
    }
    const result = await twilioCheck({
      accountSid,
      authToken,
      serviceSid,
      phone: parsed.phone,
      code,
    });
    if (result === "error") return json({ error: "check_failed" }, 502);
    approved = result === "approved";
  }

  if (!approved) {
    await recordEvent(restURL, serviceKey, {
      phone_hash: phoneHash,
      prefix: parsed.prefix,
      ip_hash: ipHash,
      kind: "check_fail",
    });
    return json({ error: "mismatch", msg: "That code didn't match" }, 403);
  }

  await recordEvent(restURL, serviceKey, {
    phone_hash: phoneHash,
    prefix: parsed.prefix,
    ip_hash: ipHash,
    kind: "check_ok",
  });

  return mintSession({
    supabaseURL,
    serviceKey,
    anonKey,
    phone: parsed.phone,
  });
});
