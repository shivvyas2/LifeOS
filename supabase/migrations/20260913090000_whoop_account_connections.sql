-- Account-owned credentials, readable only inside authenticated Edge Functions.
create table if not exists public.whoop_connections (
  user_id uuid primary key references auth.users on delete cascade,
  access_token text not null,
  refresh_token text,
  access_expires_at timestamptz not null,
  refresh_lock uuid,
  refresh_locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.whoop_connections enable row level security;
revoke all on public.whoop_connections from anon, authenticated;
grant all on public.whoop_connections to service_role;

create or replace function public.claim_whoop_refresh(p_user_id uuid, p_lock uuid)
returns setof public.whoop_connections
language sql security definer set search_path = public
as $$
  update public.whoop_connections
  set refresh_lock = p_lock, refresh_locked_until = now() + interval '30 seconds'
  where user_id = p_user_id
    and (refresh_locked_until is null or refresh_locked_until < now())
  returning *;
$$;
revoke all on function public.claim_whoop_refresh(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_whoop_refresh(uuid, uuid) to service_role;
