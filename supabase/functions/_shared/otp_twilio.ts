import { json, restHeaders } from "./otp_guard.ts";

export async function twilioStart(args: {
  accountSid: string;
  authToken: string;
  serviceSid: string;
  phone: string;
}): Promise<{ ok: true } | { ok: false; kind: string }> {
  const body = new URLSearchParams();
  body.set("To", args.phone);
  body.set("Channel", "sms");

  let response: Response;
  try {
    response = await fetch(
      `https://verify.twilio.com/v2/Services/${args.serviceSid}/Verifications`,
      {
        method: "POST",
        headers: {
          Authorization: basic(args.accountSid, args.authToken),
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body,
      },
    );
  } catch (error) {
    console.error(`twilio start threw: ${String(error)}`);
    return { ok: false, kind: "send_failed" };
  }

  if (response.ok) return { ok: true };
  const text = await response.text();
  console.error(`twilio start failed: ${response.status} ${text.slice(0, 180)}`);
  return { ok: false, kind: classifyTwilioFailure(response.status, text) };
}

export function classifyTwilioFailure(status: number, body: string): string {
  let code: number | undefined;
  try {
    const parsed = JSON.parse(body) as { code?: number };
    if (typeof parsed.code === "number") code = parsed.code;
  } catch {
    // Twilio sometimes returns HTML. Treat it as a generic send failure.
  }

  if (status === 429 || code === 60203 || code === 20429) return "rate_limited";
  if (code === 21408 || code === 21612) return "sms_region";
  if (code === 21608 || code === 21610) return "sms_unverified";
  if (code === 21211 || code === 21614 || code === 60200) return "invalid_phone";
  if (code === 20003 || code === 20404) return "server_not_configured";
  return "send_failed";
}

export async function twilioCheck(args: {
  accountSid: string;
  authToken: string;
  serviceSid: string;
  phone: string;
  code: string;
}): Promise<"approved" | "denied" | "error"> {
  const body = new URLSearchParams();
  body.set("To", args.phone);
  body.set("Code", args.code);

  const response = await fetch(
    `https://verify.twilio.com/v2/Services/${args.serviceSid}/VerificationCheck`,
    {
      method: "POST",
      headers: {
        Authorization: basic(args.accountSid, args.authToken),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    },
  );

  if (!response.ok) {
    const text = await response.text();
    console.error(`twilio check failed: ${response.status} ${text.slice(0, 180)}`);
    if (response.status === 404 || response.status === 429) return "denied";
    return "error";
  }

  const payload = await response.json() as { status?: string };
  return payload.status === "approved" ? "approved" : "denied";
}

function basic(sid: string, token: string): string {
  return `Basic ${btoa(`${sid}:${token}`)}`;
}

export async function mintSession(args: {
  supabaseURL: string;
  serviceKey: string;
  anonKey: string;
  phone: string;
}): Promise<Response> {
  const email = syntheticEmail(args.phone);
  const existingID = await userIDForPhone(args.supabaseURL, args.serviceKey, args.phone);

  if (existingID) {
    await fetch(`${args.supabaseURL}/auth/v1/admin/users/${existingID}`, {
      method: "PUT",
      headers: restHeaders(args.serviceKey),
      body: JSON.stringify({
        phone: args.phone,
        phone_confirm: true,
        email,
        email_confirm: true,
      }),
    });
  } else {
    const created = await fetch(`${args.supabaseURL}/auth/v1/admin/users`, {
      method: "POST",
      headers: restHeaders(args.serviceKey),
      body: JSON.stringify({
        phone: args.phone,
        phone_confirm: true,
        email,
        email_confirm: true,
      }),
    });
    if (!created.ok) {
      const text = await created.text();
      console.error(`create user failed: ${created.status} ${text.slice(0, 180)}`);
      return json({ error: "session_failed" }, 500);
    }
  }

  const linkResponse = await fetch(`${args.supabaseURL}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: restHeaders(args.serviceKey),
    body: JSON.stringify({ type: "magiclink", email }),
  });
  if (!linkResponse.ok) {
    const text = await linkResponse.text();
    console.error(`generate link failed: ${linkResponse.status} ${text.slice(0, 180)}`);
    return json({ error: "session_failed" }, 500);
  }

  const link = await linkResponse.json() as {
    hashed_token?: string;
    properties?: { hashed_token?: string };
  };
  const tokenHash = link.properties?.hashed_token ?? link.hashed_token;
  if (!tokenHash) return json({ error: "session_failed" }, 500);

  const verify = await fetch(`${args.supabaseURL}/auth/v1/verify`, {
    method: "POST",
    headers: {
      apikey: args.anonKey,
      Authorization: `Bearer ${args.anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "email", token_hash: tokenHash }),
  });
  const text = await verify.text();
  if (!verify.ok) {
    console.error(`verify link failed: ${verify.status} ${text.slice(0, 180)}`);
    return json({ error: "session_failed" }, 500);
  }
  return new Response(text, {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function userIDForPhone(supabaseURL: string, serviceKey: string, phone: string): Promise<string | null> {
  const response = await fetch(`${supabaseURL}/rest/v1/rpc/otp_user_id_for_phone`, {
    method: "POST",
    headers: restHeaders(serviceKey),
    body: JSON.stringify({ p_phone: phone }),
  });
  if (!response.ok) return null;
  const id = await response.json();
  return typeof id === "string" && id.length > 0 ? id : null;
}

function syntheticEmail(phone: string): string {
  return `p${phone.replace(/\D/g, "")}@phone.lifeos.internal`;
}
