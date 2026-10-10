// Runs a migration and an access-check script in PGlite (Postgres in
// WebAssembly), so row-level security can be checked without Docker.
// Supabase's auth schema, roles and project_tasks are stubbed just enough.
//   deno run -A supabase/tests/run_rls.ts <migration.sql> <check.sql>
import { PGlite } from "npm:@electric-sql/pglite@0.2.17";

const [migration, check] = Deno.args;
const db = new PGlite();
await db.exec(`
  create role authenticated nologin;
  create role anon nologin;
  create schema auth;
  create table auth.users (id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid
  $$;
  grant usage on schema auth to authenticated;
  grant execute on function auth.uid() to authenticated;
  grant select on auth.users to authenticated;
  create table public.project_tasks (id uuid primary key);
  grant usage on schema public to authenticated;
  alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
`);
await db.exec(await Deno.readTextFile(migration));
await db.exec(`grant select, insert, update, delete on all tables in schema public to authenticated;`);
try {
  await db.exec(await Deno.readTextFile(check));
  console.log("RLS CHECK PASSED");
} catch (error) {
  console.error("RLS CHECK FAILED:", (error as Error).message);
  Deno.exit(1);
}
