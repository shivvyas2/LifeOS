import { assertEquals } from "jsr:@std/assert@1";
import { SEND_FAILURE_STATUS, classifyTwilioFailure } from "./otp_twilio.ts";

// 21608 and 21610 shared one bucket whose copy explained neither. One is a
// developer misconfiguration that cannot happen on a paid account; the other is
// a user action with a user remedy.
Deno.test("a trial account sending to an unverified number is its own kind", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 21608 })),
    "sms_trial_unverified",
  );
});

Deno.test("an opted-out recipient is its own kind", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 21610 })),
    "sms_opted_out",
  );
});

Deno.test("an unregistered A2P campaign is named rather than generic", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 30034 })),
    "sms_unregistered_campaign",
  );
});

Deno.test("a blocked Verify delivery is named rather than generic", () => {
  assertEquals(
    classifyTwilioFailure(400, JSON.stringify({ code: 60410 })),
    "sms_blocked",
  );
});

Deno.test("a 429 is rate limiting whatever the body says", () => {
  assertEquals(classifyTwilioFailure(429, "{}"), "rate_limited");
});

Deno.test("an HTML body falls back to a generic send failure", () => {
  assertEquals(
    classifyTwilioFailure(500, "<html>Bad Gateway</html>"),
    "send_failed",
  );
});

Deno.test("every kind the classifier can return has a status", () => {
  const kinds = [
    "rate_limited",
    "sms_region",
    "sms_trial_unverified",
    "sms_opted_out",
    "sms_unregistered_campaign",
    "sms_blocked",
    "invalid_phone",
    "server_not_configured",
  ];
  for (const kind of kinds) {
    assertEquals(typeof SEND_FAILURE_STATUS[kind], "number", kind);
  }
});
