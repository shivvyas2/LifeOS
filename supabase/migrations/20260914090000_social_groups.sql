-- Private social groups. Invitations do not grant chat or leaderboard access.
create table public.social_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  description text not null default '' check (char_length(description) <= 240),
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.group_members (
  group_id uuid not null references public.social_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('invited', 'accepted')),
  shares_activity boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user on public.group_members(user_id, status);
create table public.group_messages (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.social_groups(id) on delete cascade,
  sender uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  client_id uuid not null,
  created_at timestamptz not null default now(),
  unique(sender, client_id)
);
create index group_messages_timeline on public.group_messages(group_id, id desc);
create table public.group_activity (
  user_id uuid primary key references auth.users(id) on delete cascade,
  streak integer check (streak >= 0),
  days_tracked integer check (days_tracked >= 0),
  workouts integer check (workouts >= 0),
  updated_at timestamptz not null default now()
);

alter table public.social_groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_messages enable row level security;
alter table public.group_activity enable row level security;

-- Definer helper avoids recursive membership policies. The caller identity
-- comes only from auth.uid(), never from a supplied user ID.
create function public.is_group_member(p_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.group_members where group_id=p_group and user_id=auth.uid() and status='accepted');
$$;
revoke all on function public.is_group_member(uuid) from public, anon;
grant execute on function public.is_group_member(uuid) to authenticated;
create policy "members and invitees see group" on public.social_groups for select to authenticated
 using (exists(select 1 from public.group_members m where m.group_id=id and m.user_id=auth.uid()));
create policy "members see roster and own invite" on public.group_members for select to authenticated
 using(user_id=auth.uid() or public.is_group_member(group_id));
create policy "accepted members read chat" on public.group_messages for select to authenticated
 using(public.is_group_member(group_id));
create policy "own activity" on public.group_activity for select to authenticated using(user_id=auth.uid());
-- All writes go through constrained, transactional RPCs. Also revoke
-- TRUNCATE, which bypasses row-level security.
revoke all on public.social_groups, public.group_members, public.group_messages, public.group_activity from anon, authenticated;
grant select on public.social_groups, public.group_members, public.group_messages, public.group_activity to authenticated;

create function public.create_social_group(p_name text, p_description text, p_invitees uuid[], p_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target uuid; caller uuid := auth.uid();
begin
 if caller is null then raise exception 'Sign in to create a group'; end if;
 if exists(select 1 from public.social_groups where id=p_id and owner_id=caller) then return p_id; end if;
 if cardinality(p_invitees)>49 then raise exception 'Groups support up to 50 people'; end if;
 insert into public.social_groups(id,name,description,owner_id) values(p_id,btrim(p_name),btrim(p_description),caller);
 insert into public.group_members(group_id,user_id,status) values(p_id,caller,'accepted');
 for target in select distinct unnest(p_invitees) loop
  if target=caller then continue; end if;
  if not exists(select 1 from public.friendships where status='accepted' and
   ((requester=caller and addressee=target) or (requester=target and addressee=caller))) then
   raise exception 'Only accepted friends can be invited';
  end if;
  insert into public.group_members(group_id,user_id,status) values(p_id,target,'invited');
 end loop;
 return p_id;
end $$;

create function public.invite_group_member(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
 -- Serialise the capacity check and membership writes.
 perform 1 from public.social_groups where id=p_group and owner_id=auth.uid() for update;
 if not found then raise exception 'Only the group owner can invite people'; end if;
 if exists(select 1 from public.group_members where group_id=p_group and user_id=p_user) then return; end if;
 if (select count(*) from public.group_members where group_id=p_group)>=50 then raise exception 'This group is full'; end if;
 if not exists(select 1 from public.friendships where status='accepted' and
  ((requester=auth.uid() and addressee=p_user) or (requester=p_user and addressee=auth.uid()))) then
  raise exception 'Only accepted friends can be invited';
 end if;
 insert into public.group_members(group_id,user_id,status) values(p_group,p_user,'invited');
end $$;

create function public.answer_group_invite(p_group uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if p_accept then
  update public.group_members set status='accepted',joined_at=now() where group_id=p_group and user_id=auth.uid() and status='invited';
 else
  delete from public.group_members where group_id=p_group and user_id=auth.uid() and status='invited';
 end if;
end $$;

create function public.leave_social_group(p_group uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare owner uuid; successor uuid;
begin
 select owner_id into owner from public.social_groups where id=p_group for update;
 if not public.is_group_member(p_group) then raise exception 'Join this group first'; end if;
 if owner=auth.uid() then
  select user_id into successor from public.group_members where group_id=p_group and status='accepted' and user_id<>auth.uid() order by joined_at,user_id limit 1;
  if successor is null then delete from public.social_groups where id=p_group; return; end if;
  update public.social_groups set owner_id=successor where id=p_group;
 end if;
 delete from public.group_members where group_id=p_group and user_id=auth.uid();
end $$;

create function public.remove_group_member(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
 perform 1 from public.social_groups where id=p_group and owner_id=auth.uid() for update;
 if not found or p_user=auth.uid() then raise exception 'Only the owner can remove other members'; end if;
 delete from public.group_members where group_id=p_group and user_id=p_user;
end $$;

create function public.send_group_message(p_group uuid, p_body text, p_client_id uuid) returns bigint
language plpgsql security definer set search_path = '' as $$
declare message_id bigint;
begin
 -- A concurrent removal cannot race a new send into the group.
 perform 1 from public.social_groups where id=p_group for update;
 if not public.is_group_member(p_group) then raise exception 'You are no longer a member of this group'; end if;
 insert into public.group_messages(group_id,sender,body,client_id) values(p_group,auth.uid(),btrim(p_body),p_client_id)
 on conflict(sender,client_id) do nothing returning id into message_id;
 if message_id is null then
  select id into message_id from public.group_messages where sender=auth.uid() and client_id=p_client_id and group_id=p_group and body=btrim(p_body);
  if message_id is null then raise exception 'This send identifier was already used'; end if;
 end if;
 return message_id;
end $$;

create function public.set_group_activity_sharing(p_group uuid, p_shares boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
 update public.group_members set shares_activity=p_shares where group_id=p_group and user_id=auth.uid() and status='accepted';
 if not found then raise exception 'Join this group first'; end if;
end $$;

create function public.publish_group_activity(p_streak integer, p_days_tracked integer, p_workouts integer) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to share activity'; end if;
 if not exists(select 1 from public.group_members where user_id=auth.uid() and status='accepted' and shares_activity) then return; end if;
 insert into public.group_activity(user_id,streak,days_tracked,workouts) values(auth.uid(),p_streak,p_days_tracked,p_workouts)
 on conflict(user_id) do update set streak=excluded.streak,days_tracked=excluded.days_tracked,workouts=excluded.workouts,updated_at=now();
end $$;

create function public.group_leaderboard(p_group uuid, p_metric text)
returns table(user_id uuid,display_name text,avatar_path text,score integer,rank_position bigint,updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
 if not public.is_group_member(p_group) then raise exception 'Join this group to see its leaderboard'; end if;
 if p_metric not in ('streak','days_tracked','workouts') then raise exception 'Unknown leaderboard metric'; end if;
 return query
 with scores as (
  select a.user_id,p.display_name,p.avatar_path,a.updated_at,
   case p_metric when 'streak' then a.streak when 'days_tracked' then a.days_tracked else a.workouts end as value
  from public.group_members m join public.group_activity a on a.user_id=m.user_id
   join public.profiles p on p.user_id=m.user_id
  where m.group_id=p_group and m.status='accepted' and m.shares_activity
 )
 select s.user_id,s.display_name,s.avatar_path,s.value,rank() over(order by s.value desc),s.updated_at
 from scores s where s.value is not null order by s.value desc,s.display_name,s.user_id;
end $$;

-- SECURITY DEFINER RPCs are never callable by anonymous clients.
revoke all on function public.create_social_group(text,text,uuid[],uuid), public.invite_group_member(uuid,uuid),
 public.answer_group_invite(uuid,boolean), public.leave_social_group(uuid), public.remove_group_member(uuid,uuid),
 public.send_group_message(uuid,text,uuid), public.set_group_activity_sharing(uuid,boolean),
 public.publish_group_activity(integer,integer,integer), public.group_leaderboard(uuid,text) from public, anon;
grant execute on function public.create_social_group(text,text,uuid[],uuid), public.invite_group_member(uuid,uuid),
 public.answer_group_invite(uuid,boolean), public.leave_social_group(uuid), public.remove_group_member(uuid,uuid),
 public.send_group_message(uuid,text,uuid), public.set_group_activity_sharing(uuid,boolean),
 public.publish_group_activity(integer,integer,integer), public.group_leaderboard(uuid,text) to authenticated;
