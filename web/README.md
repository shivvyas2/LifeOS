# almanac.shivvyas.com

A two file static site whose only job is to make Plaid's OAuth redirect land
back inside the iOS app.

Banks that use OAuth (Chase, Wells Fargo, Capital One and most large US
institutions) do not accept a bank login inside Plaid Link. Link hands the
browser to the bank, the bank authenticates, and the bank sends the browser to
a redirect URI that Plaid was told about in advance. On iOS that redirect URI
has to be a universal link, because a custom scheme like `almanac://` cannot be
registered with Plaid and would not survive the hop through Safari.

So this site exists to say one thing to iOS: the path `/plaid-oauth` on this
domain belongs to `Z42YU5W6WY.com.shivvyas.lifeos`.

## Files

- `.well-known/apple-app-site-association` is the claim itself. iOS fetches it
  over https, with no redirects, and caches it. `vercel.json` forces the
  `application/json` content type, without which iOS ignores the file and every
  OAuth connection silently falls back to Safari.
- `plaid-oauth.html` is the fallback page a person sees only when the universal
  link does not resolve.

## Setup this repository cannot do for you

1. **DNS.** Point `almanac.shivvyas.com` at Vercel, then add the domain to the
   `shivvyas-projects/almanac-links` project, which already serves this site at
   https://almanac-links.vercel.app.
2. **Plaid dashboard.** Team Settings, API, Allowed redirect URIs: add
   `https://almanac.shivvyas.com/plaid-oauth`. Plaid refuses to mint a link
   token carrying a redirect URI it has not been shown, so the app's Connect
   button starts failing the moment `PLAID_REDIRECT_URI` is set and stops
   failing once this is registered. Do this one first.
3. **Supabase.** `supabase secrets set PLAID_REDIRECT_URI=https://almanac.shivvyas.com/plaid-oauth`
4. **Apple Developer portal.** The App ID needs the Associated Domains
   capability. Automatic signing in Xcode usually adds it; a manual profile
   will not.

## Checking it worked

    curl -sI https://almanac.shivvyas.com/.well-known/apple-app-site-association

Wants `200` and `content-type: application/json`. A redirect or an HTML
content type means iOS will not read it. After that, a freshly installed build
on a real device is the only honest test: the association is fetched at install
time, so editing this file does not change an app already on the phone.
