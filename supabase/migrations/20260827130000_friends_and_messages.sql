-- Who can be found. One row per account, written by its owner, readable by
-- any signed-in user because search is the point. Nothing sensitive lives
-- here: a display name and nothing else.
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  updated_at timestamptz not null default now()
);

create index profiles_display_name on public.profiles
  using gin (to_tsvector('simple', display_name));

alter table public.profiles enable row level security;

create policy "profiles are searchable by the signed in"
  on public.profiles for select to authenticated using (true);
create policy "own profile insert"
  on public.profiles for insert to authenticated
  with check (user_id = auth.uid());
create policy "own profile update"
  on public.profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A friendship is one row, whoever asked first. `pending` until the
-- addressee accepts. The unique pair constraint is on the ordered pair,
-- and the API guards the reverse direction before inserting.
create table public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null references auth.users (id) on delete cascade,
  addressee uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee),
  check (requester <> addressee)
);

create index friendships_addressee on public.friendships (addressee, status);
create index friendships_requester on public.friendships (requester, status);

alter table public.friendships enable row level security;

create policy "participants see their friendships"
  on public.friendships for select to authenticated
  using (auth.uid() in (requester, addressee));
create policy "ask for a friendship"
  on public.friendships for insert to authenticated
  with check (requester = auth.uid() and status = 'pending');
create policy "addressee answers"
  on public.friendships for update to authenticated
  using (addressee = auth.uid())
  with check (addressee = auth.uid() and status = 'accepted');
create policy "either side may end it"
  on public.friendships for delete to authenticated
  using (auth.uid() in (requester, addressee));

-- Plain text messages between accepted friends. No edits, no deletes in v1:
-- a message is a fact once sent.
create table public.messages (
  id bigint generated always as identity primary key,
  sender uuid not null references auth.users (id) on delete cascade,
  recipient uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  check (sender <> recipient)
);

create index messages_conversation on public.messages
  (least(sender, recipient), greatest(sender, recipient), created_at);

alter table public.messages enable row level security;

create policy "participants read their conversation"
  on public.messages for select to authenticated
  using (auth.uid() in (sender, recipient));
create policy "friends may message"
  on public.messages for insert to authenticated
  with check (
    sender = auth.uid()
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester = sender and f.addressee = recipient)
          or (f.requester = recipient and f.addressee = sender))
    )
  );
