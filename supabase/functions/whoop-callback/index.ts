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

  // "Sign in on another device": the app issues a `manual-` state when the
  // user completes authorization in a desktop browser, which cannot hand back
  // to lifeos://. Render the code for transcription instead of redirecting.
  if (state?.startsWith("manual-")) {
    return new Response(page(code, error), {
      status: 200,
      headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
    });
  }

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

/// Shown only for the "sign in on another device" flow. The code is single-use
/// and short-lived, and is useless without the PKCE verifier, which never
/// leaves the phone.
function page(code: string | null, error: string | null): string {
  const body = error
    ? `<p class="err">Whoop returned: ${escapeHtml(error)}</p>
       <p>Nothing was connected. Start again in Life OS.</p>`
    : code
    ? `<p>Copy this code and paste it into Life OS:</p>
       <div class="code" id="c">${escapeHtml(code)}</div>
       <button onclick="navigator.clipboard.writeText(document.getElementById('c').textContent.trim())">Copy code</button>
       <p class="hint">Single use, and it expires in a few minutes.</p>`
    : `<p class="err">No code was returned.</p>`;

  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Life OS — Whoop</title><style>
:root{color-scheme:light dark}
body{font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
     max-width:34rem;margin:0 auto;padding:3rem 1.5rem}
h1{font-size:1.25rem;margin:0 0 1rem}
.code{font:15px ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-all;
      background:rgba(127,127,127,.14);padding:1rem;border-radius:12px;margin:1rem 0}
button{font:inherit;font-weight:600;padding:.6rem 1.1rem;border:0;border-radius:999px;
       background:#F0572E;color:#fff}
.hint{opacity:.6;font-size:.875rem}.err{color:#c0392b}
</style></head><body><h1>Whoop authorization</h1>${body}</body></html>`;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!)
  );
}
