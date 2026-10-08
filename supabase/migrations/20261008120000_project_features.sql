-- Features: the plan between a project's scope and its tasks. Each may link
-- to a branch; its stage is worked out on a member's phone from GitHub and
-- written here, so members without access to the repo see it too. Same
-- membership rules as milestones.

create table public.project_features (
  id uuid primary key,
  project_id uuid not null references public.projects (id) on delete cascade,
  milestone_id uuid references public.project_milestones (id) on delete set null,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  note text not null default '' check (char_length(note) <= 280),
  position integer not null default 0,
  branch text check (branch is null or char_length(branch) between 1 and 255),
  stage text not null default 'planned' check (stage in ('planned', 'building', 'review', 'done')),
  stage_detail text not null default '' check (char_length(stage_detail) <= 80),
  pr_number integer check (pr_number is null or pr_number > 0),
  stage_checked_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index project_features_project_idx on public.project_features (project_id, updated_at);

create trigger project_features_touch before insert or update on public.project_features
  for each row execute function public.touch_updated_at();

alter table public.project_features enable row level security;

create policy "members read features" on public.project_features
  for select to authenticated using (public.is_project_member(project_id));
create policy "members add features" on public.project_features
  for insert to authenticated with check (public.is_project_member(project_id));
create policy "members edit features" on public.project_features
  for update to authenticated using (public.is_project_member(project_id))
  with check (public.is_project_member(project_id));

alter table public.project_tasks
  add column feature_id uuid references public.project_features (id) on delete set null;
