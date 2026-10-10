// Gives a sibling LifeOS app a session of its own for the account the caller
// is signed in to. See SharedSignIn.swift for why tokens are traded, not shared.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleHandoff } from "../_shared/handoff.ts";
import { sessionForEmail } from "../_shared/otp_twilio.ts";

Deno.serve((req) => {
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  return handleHandoff(req, {
    supabaseURL,
    serviceKey,
    anonKey,
    // The caller is whoever their own token says. Never an id from the body.
    resolveEmail: async (r) => {
      const authorization = r.headers.get("Authorization");
      if (!authorization) return null;
      const client = createClient(supabaseURL, anonKey, { global: { headers: { Authorization: authorization } } });
      const { data, error } = await client.auth.getUser();
      return error || !data.user?.email ? null : data.user.email;
    },
    mint: (email) => sessionForEmail({ supabaseURL, serviceKey, anonKey, email }),
  });
});
