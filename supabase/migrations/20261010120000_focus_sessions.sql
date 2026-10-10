-- One row per finished focus session, written by LifeOS or LifeOS Focus and
-- read by both. The id is the device's own record id, so a resend after a
-- lost response is a duplicate the insert ignores, never a second row.
create table public.focus_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mood text not null check (mood in ('focus', 'brainstorm', 'relax', 'sleep')),
  source text not null check (source in ('soundscape', 'appleMusic', 'silence')),
  started_at timestamptz not null,
  ended_at timestamptz,
  focused_seconds integer not null check (focused_seconds >= 0),
  blocks_completed integer not null default 0 check (blocks_completed >= 0),
  project_task_id uuid references public.project_tasks (id) on delete set null,
  created_at timestamptz not null default now()
);

create index focus_sessions_user_started on public.focus_sessions (user_id, started_at desc);

alter table public.focus_sessions enable row level security;

create policy "own focus sessions are readable" on public.focus_sessions
  for select to authenticated using (user_id = auth.uid());
create policy "own focus sessions can be added" on public.focus_sessions
  for insert to authenticated with check (user_id = auth.uid());
create policy "own focus sessions can be deleted" on public.focus_sessions
  for delete to authenticated using (user_id = auth.uid());
-- No update policy: a session is final once it ends.
