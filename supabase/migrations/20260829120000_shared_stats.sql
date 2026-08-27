-- The three figures under a name, shared with friends only, and only when
-- their owner turned sharing on.
--
-- A separate table rather than columns on `profiles`, for one reason: the
-- select policy on `profiles` is `using (true)` for every signed-in user,
-- because that is what makes search work, and Postgres row level security is
-- row level. A `shares_stats` column there would be world-readable along with
-- the numbers beside it, and "opt in" would mean opting into showing everyone.
-- Its own table gets its own policy, and that policy can name friendship.
create table public.profile_stats (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- The owner's answer, kept even when the numbers are null, so turning
  -- sharing off and on again does not read as a fresh decision.
  shares boolean not null default false,
  -- Nullable rather than zero-defaulted. Zero is a real figure, and a person
  -- on their first day has genuinely done no workouts; null is "not sent",
  -- which is what a row looks like before the first push or after sharing is
  -- switched off. The screen omits what it does not know rather than showing
  -- a zero nobody earned.
  streak integer check (streak >= 0),
  days_tracked integer check (days_tracked >= 0),
  workouts integer check (workouts >= 0),
  updated_at timestamptz not null default now()
);

alter table public.profile_stats enable row level security;

-- Yourself always, and an accepted friend. Pending is not enough: asking to
-- be someone's friend must not be a way to read their figures while they
-- decide, or the request itself becomes the attack.
create policy "own stats and accepted friends' stats"
  on public.profile_stats for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester = auth.uid() and f.addressee = profile_stats.user_id)
          or (f.addressee = auth.uid() and f.requester = profile_stats.user_id)
        )
    )
  );

create policy "own stats insert"
  on public.profile_stats for insert to authenticated
  with check (user_id = auth.uid());
create policy "own stats update"
  on public.profile_stats for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own stats delete"
  on public.profile_stats for delete to authenticated
  using (user_id = auth.uid());

-- The device writes the whole row on every push, so the grants are the whole
-- row. `friendships` is read by the policy above on behalf of the caller;
-- that table's own policy already restricts it to the caller's rows, and the
-- `exists` here only ever asks about rows the caller participates in.
grant select, insert, update, delete on public.profile_stats to authenticated;
