-- Claims the connection row for the duration of the calling transaction.
--
-- The lock is the whole reason the tokens are server side. Fitbit rotates the
-- refresh token on every use, so two devices syncing at once would each
-- rotate it and invalidate the other, and the user would be signed out by
-- their own second phone.
create or replace function public.claim_fitbit_connection(p_user_id uuid)
returns public.fitbit_connections
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.fitbit_connections;
begin
  select * into claimed
  from public.fitbit_connections
  where user_id = p_user_id
  for update;
  return claimed;
end;
$$;

revoke all on function public.claim_fitbit_connection(uuid) from public, anon, authenticated;
