// Start a Twilio Verify SMS. Twilio credentials never leave this function.
//
//   supabase secrets set TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_VERIFY_SERVICE_SID=...
//
import {
  TEST_PHONE,
  allowStart,
  clientIP,
  hashIdentity,
  json,
  parsePhone,
  recordEvent,
} from "../_shared/otp_guard.ts";
import { twilioStart } from "../_shared/otp_twilio.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceKey) return json({ error: "server_not_configured" }, 500);

  let body: { phone?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const parsed = parsePhone(body.phone);
  if (!parsed.ok) return json({ error: parsed.error }, parsed.status);

  const pepper = Deno.env.get("OTP_PEPPER") ?? serviceKey;
  const phoneHash = await hashIdentity(parsed.phone, pepper);
  const ipHash = await hashIdentity(clientIP(req), pepper);
  const restURL = `${supabaseURL}/rest/v1`;

  const allowed = await allowStart({
    restURL,
    serviceKey,
    phoneHash,
    prefix: parsed.prefix,
    ipHash,
  }).catch(() => null);
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

  await recordEvent(restURL, serviceKey, {
    phone_hash: phoneHash,
    prefix: parsed.prefix,
    ip_hash: ipHash,
    kind: "start",
  });

  if (parsed.phone === TEST_PHONE) return json({ ok: true }, 200);

  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const serviceSid = Deno.env.get("TWILIO_VERIFY_SERVICE_SID");
  if (!accountSid || !authToken || !serviceSid) {
    return json({ error: "server_not_configured" }, 500);
  }

  const sent = await twilioStart({
    accountSid,
    authToken,
    serviceSid,
    phone: parsed.phone,
  });
  if (!sent.ok) {
    if (sent.status === 429 || sent.status === 60203) return json({ error: "rate_limited" }, 429);
    return json({ error: "send_failed" }, 502);
  }

  return json({ ok: true }, 200);
});
