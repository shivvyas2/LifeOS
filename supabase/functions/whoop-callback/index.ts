// OAuth redirect bridge.
//
// Whoop requires a redirect URL starting with https, but the authorization
// code has to reach an iOS app, which is addressed by a custom scheme. This
// function is the hop between: Whoop redirects the browser here, and this
// immediately 302s to lifeos://whoop-callback carrying the same parameters.
//
// It holds no secret and makes no decisions. PKCE and the `state` check still
// happen in the app, so this hop cannot be used to inject a forged code — an
// attacker who reaches this endpoint only gets a redirect back to an app that
// will reject a `state` it did not issue.

const APP_SCHEME_URL = "lifeos://whoop-callback";

Deno.serve((req: Request) => {
  const incoming = new URL(req.url);

  const code = incoming.searchParams.get("code");
  const state = incoming.searchParams.get("state");
  const error = incoming.searchParams.get("error");

  const target = new URL(APP_SCHEME_URL);
  // Forward the failure too, so the app can tell "denied" from "never came back".
  if (error) {
    target.searchParams.set("error", error);
    if (state) target.searchParams.set("state", state);
  } else {
    if (code) target.searchParams.set("code", code);
    if (state) target.searchParams.set("state", state);
  }

  return new Response(null, {
    status: 302,
    headers: {
      Location: target.toString(),
      // This response is a one-shot redirect tied to a single auth attempt.
      "Cache-Control": "no-store",
    },
  });
});
