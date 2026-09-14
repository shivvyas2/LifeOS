begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Disposable identities and messages exist only inside this rolled-back transaction.
insert into auth.users(id) values
 ('a6140000-0000-4000-8000-000000000001'),
 ('a6140000-0000-4000-8000-000000000002'),
 ('a6140000-0000-4000-8000-000000000003');
insert into public.profiles(user_id,display_name) values
 ('a6140000-0000-4000-8000-000000000001','Social QA Owner'),
 ('a6140000-0000-4000-8000-000000000002','Social QA Friend'),
 ('a6140000-0000-4000-8000-000000000003','Social QA Outsider');
insert into public.friendships(requester,addressee,status) values
 ('a6140000-0000-4000-8000-000000000001','a6140000-0000-4000-8000-000000000002','accepted');
set local role authenticated;
select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000001',true);
select lives_ok($$select public.create_social_group('QA circle','Private test',array['a6140000-0000-4000-8000-000000000002'::uuid],'b6140000-0000-4000-8000-000000000001')$$,'Owner can create a group and invite a friend');
select lives_ok($$select public.create_social_group('QA circle','Private test',array['a6140000-0000-4000-8000-000000000002'::uuid],'b6140000-0000-4000-8000-000000000001')$$,'Retrying creation is idempotent');
select is((select count(*) from public.group_members where group_id='b6140000-0000-4000-8000-000000000001'),2::bigint,'Group has one owner and one invitation');
select ok(not has_table_privilege('authenticated','public.group_messages','TRUNCATE'),'Authenticated clients cannot truncate messages');
select throws_ok($$select public.invite_group_member('b6140000-0000-4000-8000-000000000001','a6140000-0000-4000-8000-000000000003')$$,'P0001','Only accepted friends can be invited','Cannot invite an unrelated user');
select throws_ok($$select public.create_social_group('','','{}','b6140000-0000-4000-8000-000000000002')$$,'23514',null,'Blank group names are rejected');
select throws_ok($$select public.create_social_group('Atomic test','',array['a6140000-0000-4000-8000-000000000003'::uuid],'b6140000-0000-4000-8000-000000000002')$$,'P0001','Only accepted friends can be invited','Invalid invitation rejects creation atomically');
select is((select count(*) from public.social_groups where id='b6140000-0000-4000-8000-000000000002'),0::bigint,'Failed creation leaves no partial group');
select lives_ok($$select public.create_social_group('Second circle','',array['a6140000-0000-4000-8000-000000000002'::uuid],'b6140000-0000-4000-8000-000000000002')$$,'Owner can create another independent group');

select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000002',true);
select is((select count(*) from public.social_groups where id='b6140000-0000-4000-8000-000000000001'),1::bigint,'Invitee sees the invitation group');
select is((select count(*) from public.group_members where group_id='b6140000-0000-4000-8000-000000000001'),1::bigint,'Invitee cannot browse the roster');
select throws_ok($$select public.send_group_message('b6140000-0000-4000-8000-000000000001','Not yet','c6140000-0000-4000-8000-000000000001')$$,'P0001','You are no longer a member of this group','Invitation alone cannot send chat');
select throws_ok($$select * from public.group_leaderboard('b6140000-0000-4000-8000-000000000001','streak')$$,'P0001','Join this group to see its leaderboard','Invitation alone cannot see leaderboard');
select throws_ok($$update public.group_members set status='accepted' where user_id=auth.uid()$$,'42501',null,'Clients cannot forge membership directly');
select lives_ok($$select public.answer_group_invite('b6140000-0000-4000-8000-000000000001',true)$$,'Invitee can accept');
select is((select count(*) from public.group_members where group_id='b6140000-0000-4000-8000-000000000001'),2::bigint,'Accepted member sees roster');
select lives_ok($$select public.send_group_message('b6140000-0000-4000-8000-000000000001','Hello','c6140000-0000-4000-8000-000000000001')$$,'Accepted member can send');
select lives_ok($$select public.send_group_message('b6140000-0000-4000-8000-000000000001','Hello','c6140000-0000-4000-8000-000000000001')$$,'Retrying a send succeeds');
select is((select count(*) from public.group_messages where group_id='b6140000-0000-4000-8000-000000000001'),1::bigint,'Send retry does not duplicate the message');
select throws_ok($$select public.send_group_message('b6140000-0000-4000-8000-000000000001','Changed','c6140000-0000-4000-8000-000000000001')$$,'P0001','This send identifier was already used','Cannot reuse send ID for different text');
select throws_ok($$select public.send_group_message('b6140000-0000-4000-8000-000000000001',repeat('x',2001),'c6140000-0000-4000-8000-000000000002')$$,'23514',null,'Server enforces message length');
select throws_ok($$select public.invite_group_member('b6140000-0000-4000-8000-000000000001','a6140000-0000-4000-8000-000000000003')$$,'P0001','Only the group owner can invite people','Ordinary members cannot invite');
select lives_ok($$select public.publish_group_activity(5,20,0)$$,'Publishing without opt-in is a safe no-op');
select is((select count(*) from public.group_activity),0::bigint,'No scores stored before opt-in');
select lives_ok($$select public.set_group_activity_sharing('b6140000-0000-4000-8000-000000000001',true); select public.publish_group_activity(5,20,0)$$,'Member can opt in and publish');
select is((select count(*) from public.group_leaderboard('b6140000-0000-4000-8000-000000000001','workouts') where score=0),1::bigint,'A real zero remains a valid leaderboard score');
select lives_ok($$select public.answer_group_invite('b6140000-0000-4000-8000-000000000002',true)$$,'Member can join another group');
select is((select count(*) from public.group_leaderboard('b6140000-0000-4000-8000-000000000002','streak')),0::bigint,'Sharing in one group never opts into a second group');

select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000001',true);
select lives_ok($$select public.set_group_activity_sharing('b6140000-0000-4000-8000-000000000001',true); select public.publish_group_activity(5,30,4)$$,'Owner can independently opt in');
select is((select count(*) from public.group_leaderboard('b6140000-0000-4000-8000-000000000001','streak') where rank_position=1),2::bigint,'Equal scores share rank');
select is((select count(*) from public.group_activity),1::bigint,'Raw activity rows remain owner-only');
select throws_ok($$select * from public.group_leaderboard('b6140000-0000-4000-8000-000000000001','private_health')$$,'P0001','Unknown leaderboard metric','Unapproved metrics are rejected');

select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000003',true);
select is((select count(*) from public.social_groups where id='b6140000-0000-4000-8000-000000000001'),0::bigint,'Outsider cannot see group');
select is((select count(*) from public.group_messages where group_id='b6140000-0000-4000-8000-000000000001'),0::bigint,'Outsider cannot read messages');
select throws_ok($$select * from public.group_leaderboard('b6140000-0000-4000-8000-000000000001','streak')$$,'P0001','Join this group to see its leaderboard','Outsider cannot see scores');

select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000002',true);
select lives_ok($$select public.set_group_activity_sharing('b6140000-0000-4000-8000-000000000001',false)$$,'Member can revoke sharing');
select is((select count(*) from public.group_leaderboard('b6140000-0000-4000-8000-000000000001','streak')),1::bigint,'Revocation removes member from ranking');
select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000001',true);
select lives_ok($$select public.leave_social_group('b6140000-0000-4000-8000-000000000001')$$,'Owner can leave with ownership transfer');
select is((select count(*) from public.group_messages where group_id='b6140000-0000-4000-8000-000000000001'),0::bigint,'Former member loses chat access');
select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000002',true);
select is((select owner_id from public.social_groups where id='b6140000-0000-4000-8000-000000000001'),'a6140000-0000-4000-8000-000000000002'::uuid,'Remaining member is the owner');
select lives_ok($$select public.leave_social_group('b6140000-0000-4000-8000-000000000001')$$,'Last member can leave and close group');
reset role;
select is((select count(*) from public.group_messages where group_id='b6140000-0000-4000-8000-000000000001'),0::bigint,'Closing group removes its messages');
set local role anon;
select throws_ok($$select public.create_social_group('No access','','{}','b6140000-0000-4000-8000-000000000002')$$,'42501',null,'Anonymous clients cannot call group RPCs');
reset role;
select * from finish();
rollback;
