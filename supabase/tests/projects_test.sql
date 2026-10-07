-- pgTAP checks for the projects policies. Run with `supabase test db`
-- against a local stack (needs Docker).
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

-- Three people: an owner, a friend, a stranger.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test'),
  ('00000000-0000-0000-0000-0000000000b2', 'friend@test'),
  ('00000000-0000-0000-0000-0000000000c3', 'stranger@test');
insert into public.friendships (requester, addressee, status)
  values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2', 'accepted');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1"}';
insert into public.projects (id, name, owner_id)
  values ('11111111-1111-1111-1111-111111111111', 'Launch', '00000000-0000-0000-0000-0000000000a1');
select is((select count(*) from public.project_members where project_id = '11111111-1111-1111-1111-111111111111')::int, 1,
  'creating a project makes the creator a member');
insert into public.project_members (project_id, user_id)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000b2');
select throws_ok($$ insert into public.project_members (project_id, user_id)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000c3') $$,
  '42501', null, 'a stranger cannot be added');
insert into public.project_tasks (id, project_id, title)
  values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Draft');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000c3"}';
select is((select count(*) from public.projects)::int, 0, 'a non-member reads no projects');
select is((select count(*) from public.project_tasks)::int, 0, 'a non-member reads no tasks');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
update public.project_tasks set status = 'doing' where id = '22222222-2222-2222-2222-222222222222';
select is((select status from public.project_tasks where id = '22222222-2222-2222-2222-222222222222'), 'doing',
  'a member edits a task');
update public.projects set name = 'Hijacked' where id = '11111111-1111-1111-1111-111111111111';
select is((select name from public.projects where id = '11111111-1111-1111-1111-111111111111'), 'Launch',
  'a member cannot edit the project');
select throws_ok($$ insert into public.project_members (project_id, user_id)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000c3') $$,
  '42501', null, 'a member cannot add people');

select * from finish();
rollback;
