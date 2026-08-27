import { assertEquals } from "jsr:@std/assert@1";
import {
  classifyFitbitFailure,
  FITBIT_SCOPES,
  quotaRemaining,
  rangePath,
  tokenForm,
} from "./fitbit.ts";

// A refused refresh token is the end of the connection. Nothing the server
// holds can be used again, so it must be told apart from every retryable
// failure or the app retries forever against a dead credential.
Deno.test("a refused grant is its own kind", () => {
  assertEquals(
    classifyFitbitFailure(400, JSON.stringify({ errors: [{ errorType: "invalid_grant" }] })),
    "needs_reauth",
  );
  assertEquals(classifyFitbitFailure(401, ""), "needs_reauth");
});

// The quota is 150 requests per hour per user. Exhausting it is not a failure,
// it is an unfinished sync, and it must not read as a broken connection.
Deno.test("a rate limit is its own kind, because the sync resumes", () => {
  assertEquals(classifyFitbitFailure(429, ""), "rate_limited");
});

// A collection refused for a scope the user declined must not take the other
// collections down with it.
Deno.test("a refused scope is its own kind", () => {
  assertEquals(
    classifyFitbitFailure(403, JSON.stringify({ errors: [{ errorType: "insufficient_scope" }] })),
    "forbidden_scope",
  );
});

Deno.test("anything else is an opaque upstream failure", () => {
  assertEquals(classifyFitbitFailure(500, ""), "upstream_failure");
});

// Fitbit is not obliged to send JSON when it is having a bad day.
Deno.test("a non-JSON body does not throw", () => {
  assertEquals(classifyFitbitFailure(400, "<html>nope</html>"), "upstream_failure");
});

Deno.test("the quota headroom is read from the response headers", () => {
  const headers = new Headers({ "Fitbit-Rate-Limit-Remaining": "97" });
  assertEquals(quotaRemaining(headers), 97);
  assertEquals(quotaRemaining(new Headers()), null);
});

// An authorization code exchange and a refresh are the same endpoint with
// different grant types, and getting the grant_type wrong fails opaquely.
Deno.test("an exchange carries the verifier, a refresh carries the token", () => {
  const exchange = tokenForm({ code: "abc", verifier: "v", redirect_uri: "lifeos://x" });
  assertEquals(exchange.get("grant_type"), "authorization_code");
  assertEquals(exchange.get("code"), "abc");
  assertEquals(exchange.get("code_verifier"), "v");

  const refresh = tokenForm({ refresh_token: "r" });
  assertEquals(refresh.get("grant_type"), "refresh_token");
  assertEquals(refresh.get("refresh_token"), "r");
  assertEquals(refresh.get("code"), null);
});

// Every scope the app requests must be one it reads. An unused scope is a line
// on the consent screen asking for something the app will never look at.
Deno.test("the scope list holds no scope the app does not read", () => {
  const unused = ["location", "social", "settings", "electrocardiogram",
                  "irregular_rhythm_notifications", "blood_glucose"];
  for (const scope of unused) {
    assertEquals(FITBIT_SCOPES.includes(scope), false, `${scope} is requested but never read`);
  }
  assertEquals(FITBIT_SCOPES.includes("sleep"), true);
  assertEquals(FITBIT_SCOPES.includes("heartrate"), true);
});

// Each collection sits at its own path shape, and Fitbit answers a wrong one
// with a 404 that names nothing.
Deno.test("each collection knows its own path shape", () => {
  assertEquals(
    rangePath("sleep", "2026-07-28", "2026-08-26"),
    "/1.2/user/-/sleep/date/2026-07-28/2026-08-26.json",
  );
  assertEquals(
    rangePath("hrv", "2026-07-28", "2026-08-26"),
    "/1/user/-/hrv/date/2026-07-28/2026-08-26.json",
  );
  assertEquals(
    rangePath("restingHeartRate", "2026-07-28", "2026-08-26"),
    "/1/user/-/activities/heart/date/2026-07-28/2026-08-26.json",
  );
  assertEquals(
    rangePath("skinTemperature", "2026-07-28", "2026-08-26"),
    "/1/user/-/temp/skin/date/2026-07-28/2026-08-26.json",
  );
});
