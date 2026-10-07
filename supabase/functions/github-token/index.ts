import { resolveUser } from "../_shared/supabase.ts";
import { handleGitHubToken } from "../_shared/github.ts";

Deno.serve((req: Request) => handleGitHubToken(req, { resolveUser, fetch, env: (name) => Deno.env.get(name) }));
