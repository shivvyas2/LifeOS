import { assertEquals } from "jsr:@std/assert@1";
import { accountFilters, classifyPlaidFailure, linkKind } from "./plaid.ts";

// An expired bank login is not a server fault and not a retry. It is the most
// common real-world Plaid failure, since banks invalidate stored logins every
// few months, and the only fix is the user signing in again. Collapsing it
// into a generic upstream failure leaves the app spinning forever.
Deno.test("an expired bank login is its own kind", () => {
  assertEquals(
    classifyPlaidFailure(400, JSON.stringify({ error_code: "ITEM_LOGIN_REQUIRED" })),
    "item_login_required",
  );
});

Deno.test("a rate limit is its own kind, because it is worth retrying later", () => {
  assertEquals(
    classifyPlaidFailure(429, JSON.stringify({ error_code: "RATE_LIMIT_EXCEEDED" })),
    "rate_limited",
  );
});

Deno.test("anything else is an opaque upstream failure", () => {
  assertEquals(
    classifyPlaidFailure(500, JSON.stringify({ error_code: "INTERNAL_SERVER_ERROR" })),
    "upstream_failure",
  );
});

// Plaid is not obliged to send us JSON when it is having a bad day.
Deno.test("a non-JSON body does not throw", () => {
  assertEquals(classifyPlaidFailure(502, "<html>gateway timeout</html>"), "upstream_failure");
});

Deno.test("a card session narrows Link to credit cards", () => {
  assertEquals(accountFilters("credit_card"), {
    account_filters: { credit: { account_subtypes: ["credit card"] } },
  });
});

Deno.test("a bank session adds no filter, so cards still come with a bank", () => {
  assertEquals(accountFilters("bank"), {});
});

Deno.test("anything but credit_card is a bank session, including no body", () => {
  assertEquals(linkKind("credit_card"), "credit_card");
  assertEquals(linkKind(undefined), "bank");
  assertEquals(linkKind("CREDIT"), "bank");
});
