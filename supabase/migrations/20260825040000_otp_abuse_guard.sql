-- OTP abuse ledger. Service role only: the iOS client never reads this table.
-- Hashes, not phone numbers, so a database dump is not a directory of users.

create table public.otp_events (
  id bigint generated always as identity primary key,
  phone_hash text not null,
  prefix text not null,
  ip_hash text not null,
  kind text not null check (kind in ('start', 'check_fail', 'check_ok', 'blocked')),
  created_at timestamptz not null default now()
);

create index otp_events_phone_created on public.otp_events (phone_hash, created_at desc);
create index otp_events_prefix_created on public.otp_events (prefix, created_at desc);
create index otp_events_ip_created on public.otp_events (ip_hash, created_at desc);

alter table public.otp_events enable row level security;

-- Look up an existing auth user by E.164 so a successful Twilio check can
-- mint a session without GoTrue having sent the SMS.
create or replace function public.otp_user_id_for_phone(p_phone text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from auth.users where phone = p_phone limit 1;
$$;

revoke all on function public.otp_user_id_for_phone(text) from public;
revoke all on function public.otp_user_id_for_phone(text) from anon, authenticated;
grant execute on function public.otp_user_id_for_phone(text) to service_role;
