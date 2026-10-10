// Trades a signed-in app's access token for a new, independent session, so a
// sibling app on the same phone can sign in without a code and without ever
// holding the other app's refresh token.
import { json } from "./otp_guard.ts";

export async function handleHandoff(req: Request, deps: {
  supabaseURL: string;
  serviceKey: string;
  anonKey: string;
  resolveEmail: (req: Request) => Promise<string | null>;
  mint: (email: string) => Promise<Response>;
}): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const email = await deps.resolveEmail(req);
  if (!email) return json({ error: "unauthorized" }, 401);
  return deps.mint(email);
}
