-- Shared projects: a project, its members, milestones and tasks. Members read
-- and edit milestones and tasks; only the owner edits the project and its
-- membership; a member can only be a friend the owner has accepted.
-- Content rows are tombstoned (deleted_at), not deleted, so a phone that was
-- offline learns of the deletion on its next pull.

create table public.projects (
  id uuid primary key,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  scope text not null default '' check (char_length(scope) <= 240),
  starts_on date,
  ends_on date,
  colour text not null default 'tomato'
    check (colour in ('tomato', 'marigold', 'moss', 'lagoon', 'iris', 'rose')),
  owner_id uuid not null references auth.users (id) on delete cascade,
  repo text check (repo is null or repo ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, user_id)
);

create table public.project_milestones (
  id uuid primary key,
  project_id uuid not null references public.projects (id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  due_on date,
  position integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.project_tasks (
  id uuid primary key,
  project_id uuid not null references public.projects (id) on delete cascade,
  milestone_id uuid references public.project_milestones (id) on delete set null,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  notes text not null default '' check (char_length(notes) <= 2000),
  status text not null default 'todo' check (status in ('todo', 'doing', 'done')),
  owner_id uuid references auth.users (id) on delete set null,
  due_on date,
  starts_at timestamptz,
  ends_at timestamptz,
  position integer not null default 0,
  done_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index projects_updated_idx on public.projects (updated_at);
create index project_members_user_idx on public.project_members (user_id);
create index project_milestones_project_idx on public.project_milestones (project_id, updated_at);
create index project_tasks_project_idx on public.project_tasks (project_id, updated_at);
create index project_tasks_owner_idx on public.project_tasks (owner_id);

-- updated_at is the server's: it is what the sync cursor reads. The shared
-- public.touch_updated_at() from the initial schema sets it.
create trigger projects_touch before insert or update on public.projects
  for each row execute function public.touch_updated_at();
create trigger project_members_touch before insert or update on public.project_members
  for each row execute function public.touch_updated_at();
create trigger project_milestones_touch before insert or update on public.project_milestones
  for each row execute function public.touch_updated_at();
create trigger project_tasks_touch before insert or update on public.project_tasks
  for each row execute function public.touch_updated_at();

-- Membership checks bypass RLS (security definer) so the policies below can
-- ask them without recursing into project_members' own policies. Each asks
-- about the caller only, so none can be used to probe other people.
create or replace function public.is_project_member(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.project_members where project_id = p and user_id = auth.uid());
$$;

create or replace function public.is_project_owner(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.projects where id = p and owner_id = auth.uid());
$$;

create or replace function public.is_friend_of_me(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester = auth.uid() and addressee = other) or (requester = other and addressee = auth.uid()))
  );
$$;

revoke execute on function public.is_project_member(uuid) from public, anon;
revoke execute on function public.is_project_owner(uuid) from public, anon;
revoke execute on function public.is_friend_of_me(uuid) from public, anon;
grant execute on function public.is_project_member(uuid) to authenticated;
grant execute on function public.is_project_owner(uuid) to authenticated;
grant execute on function public.is_friend_of_me(uuid) to authenticated;

-- The creator becomes the owner member in the same transaction, so they can
-- read back what they just made.
create or replace function public.add_project_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.project_members (project_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (project_id, user_id) do nothing;
  return new;
end;
$$;

create trigger projects_add_owner after insert on public.projects
  for each row execute function public.add_project_owner();

alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.project_milestones enable row level security;
alter table public.project_tasks enable row level security;

create policy "members read projects" on public.projects
  for select to authenticated using (public.is_project_member(id) or owner_id = auth.uid());
create policy "people create their own projects" on public.projects
  for insert to authenticated with check (owner_id = auth.uid());
create policy "owners edit projects" on public.projects
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "members read membership" on public.project_members
  for select to authenticated using (public.is_project_member(project_id));
create policy "owners add friends" on public.project_members
  for insert to authenticated with check (
    public.is_project_owner(project_id) and role = 'member' and public.is_friend_of_me(user_id)
  );
create policy "owners remove members, members leave" on public.project_members
  for delete to authenticated using (
    role = 'member' and (public.is_project_owner(project_id) or user_id = auth.uid())
  );

create policy "members read milestones" on public.project_milestones
  for select to authenticated using (public.is_project_member(project_id));
create policy "members add milestones" on public.project_milestones
  for insert to authenticated with check (public.is_project_member(project_id));
create policy "members edit milestones" on public.project_milestones
  for update to authenticated using (public.is_project_member(project_id))
  with check (public.is_project_member(project_id));

create policy "members read tasks" on public.project_tasks
  for select to authenticated using (public.is_project_member(project_id));
create policy "members add tasks" on public.project_tasks
  for insert to authenticated with check (public.is_project_member(project_id));
revoke execute on function public.add_project_owner() from public, anon;
create policy "members edit tasks" on public.project_tasks
  for update to authenticated using (public.is_project_member(project_id))
  with check (public.is_project_member(project_id));
