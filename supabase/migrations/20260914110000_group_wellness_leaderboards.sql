-- Health comparisons require new, explicit consent. Existing streak sharing
-- does not silently expand to HRV-derived or sleep-derived scores.
alter table public.group_members add column shares_wellness boolean not null default false;
create table public.group_wellness_daily (
 user_id uuid not null references auth.users(id) on delete cascade,
 day date not null,
 effort integer check(effort between 0 and 100),
 recharge integer check(recharge between 0 and 100),
 rest integer check(rest between 0 and 100),
 effort_source text check(effort_source in ('appleHealth','whoop','fitbit')),
 recharge_source text check(recharge_source in ('appleHealth','whoop','fitbit')),
 rest_source text check(rest_source in ('appleHealth','whoop','fitbit')),
 observed_at timestamptz not null,
 primary key(user_id,day),
 check ((effort is null) = (effort_source is null)),
 check ((recharge is null) = (recharge_source is null)),
 check ((rest is null) = (rest_source is null))
);
alter table public.group_wellness_daily enable row level security;
revoke all on public.group_wellness_daily from anon, authenticated;
grant select on public.group_wellness_daily to authenticated;
create policy "own wellness scores" on public.group_wellness_daily for select to authenticated using(user_id=auth.uid());

create function public.set_group_wellness_sharing(p_group uuid,p_shares boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_shares is null then raise exception 'Choose whether to share'; end if;
 update public.group_members set shares_wellness=p_shares where group_id=p_group and user_id=auth.uid() and status='accepted';
 if not found then raise exception 'Join this group first'; end if;
end $$;

create function public.publish_group_wellness(p_days jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare item jsonb; measured_day date; measured_at timestamptz;
begin
 if auth.uid() is null then raise exception 'Sign in to share scores'; end if;
 if jsonb_typeof(p_days) is distinct from 'array' then raise exception 'Expected daily scores'; end if;
 if jsonb_array_length(p_days)>2 then raise exception 'Share only today and yesterday'; end if;
 if not exists(select 1 from public.group_members where user_id=auth.uid() and status='accepted' and shares_wellness) then return; end if;
 for item in select value from jsonb_array_elements(p_days) loop
  measured_day := (item->>'day')::date;
  measured_at := (item->>'observed_at')::timestamptz;
  -- Local dates may be a day ahead/behind UTC. Never relabel older readings as today.
  if measured_day is null or measured_day < current_date-2 or measured_day > current_date+1 then raise exception 'Score day is out of range'; end if;
  if measured_at is null or measured_at > now()+interval '5 minutes' or measured_at < now()-interval '4 days' then raise exception 'Score observation is out of range'; end if;
  insert into public.group_wellness_daily(user_id,day,effort,recharge,rest,effort_source,recharge_source,rest_source,observed_at)
  values(auth.uid(),measured_day,(item->>'effort')::integer,(item->>'recharge')::integer,(item->>'rest')::integer,
   item->>'effort_source',item->>'recharge_source',item->>'rest_source',measured_at)
  on conflict(user_id,day) do update set effort=excluded.effort,recharge=excluded.recharge,rest=excluded.rest,
   effort_source=excluded.effort_source,recharge_source=excluded.recharge_source,rest_source=excluded.rest_source,observed_at=excluded.observed_at
  where excluded.observed_at>=group_wellness_daily.observed_at;
 end loop;
end $$;

create function public.group_wellness_leaderboard(p_group uuid,p_metric text,p_day date)
returns table(user_id uuid,display_name text,avatar_path text,score integer,rank_position bigint,updated_at timestamptz,source text,day date)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_group_member(p_group) then raise exception 'Join this group to see its leaderboard'; end if;
 if p_metric is null or p_metric not in ('effort','recharge','rest') then raise exception 'Unknown leaderboard metric'; end if;
 if p_day is null or p_day<current_date-2 or p_day>current_date+1 then raise exception 'Choose today or yesterday'; end if;
 return query with scores as (
  select a.user_id,p.display_name,p.avatar_path,a.observed_at,a.day,
   case p_metric when 'effort' then a.effort when 'recharge' then a.recharge else a.rest end as value,
   case p_metric when 'effort' then a.effort_source when 'recharge' then a.recharge_source else a.rest_source end as provider
  from public.group_members m join public.group_wellness_daily a on a.user_id=m.user_id
  join public.profiles p on p.user_id=m.user_id
  where m.group_id=p_group and m.status='accepted' and m.shares_wellness and a.day=p_day
 ) select s.user_id,s.display_name,s.avatar_path,s.value,rank() over(order by s.value desc),s.observed_at,s.provider,s.day
 from scores s where s.value is not null order by s.value desc,s.display_name,s.user_id;
end $$;
revoke all on function public.set_group_wellness_sharing(uuid,boolean), public.publish_group_wellness(jsonb),public.group_wellness_leaderboard(uuid,text,date) from public,anon;
grant execute on function public.set_group_wellness_sharing(uuid,boolean), public.publish_group_wellness(jsonb),public.group_wellness_leaderboard(uuid,text,date) to authenticated;
