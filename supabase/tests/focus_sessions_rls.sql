-- Proves one user cannot read, add as someone else, or change another
-- user's focus sessions. Run with: deno run -A supabase/tests/run_rls.ts
begin;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.com');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';
insert into public.focus_sessions (id, mood, source, started_at, ended_at, focused_seconds)
values ('11111111-1111-1111-1111-111111111111', 'focus', 'soundscape', now() - interval '30 min', now(), 1500);
-- A task the server has not seen yet (created offline, or deleted before it
-- synced) must not block the session, or every upload after it fails.
insert into public.focus_sessions (id, mood, source, started_at, ended_at, focused_seconds, project_task_id)
values ('22222222-2222-2222-2222-222222222222', 'focus', 'soundscape', now() - interval '20 min', now(), 600,
        '33333333-3333-3333-3333-333333333333');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
do $$ begin
  if (select count(*) from public.focus_sessions) <> 0 then
    raise exception 'user b can read user a''s focus sessions';
  end if;
end $$;

do $$ begin
  begin
    insert into public.focus_sessions (id, user_id, mood, source, started_at, focused_seconds)
    values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'focus', 'soundscape', now(), 1);
    raise exception 'user b inserted a row as user a';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';
do $$ declare n int; begin
  update public.focus_sessions set focused_seconds = 1;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'sessions are final but an update changed % rows', n; end if;
end $$;
rollback;
