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
select public.create_social_group('Wellness QA','',array['a6140000-0000-4000-8000-000000000002'::uuid],'b6140000-0000-4000-8000-000000000001');
select public.create_social_group('Other QA','',array['a6140000-0000-4000-8000-000000000002'::uuid],'b6140000-0000-4000-8000-000000000002');
select public.set_group_activity_sharing('b6140000-0000-4000-8000-000000000001',true);
select ok(not (select shares_wellness from public.group_members where group_id='b6140000-0000-4000-8000-000000000001' and user_id=auth.uid()),'Old activity sharing does not grant health-score consent');
select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',80,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now())));
select is((select count(*) from public.group_wellness_daily),0::bigint,'No scores stored without health consent');
select public.set_group_wellness_sharing('b6140000-0000-4000-8000-000000000001',true);
select lives_ok($$select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',80,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now())))$$,'Can publish consented daily scores');
select is((select score from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date)),80,'Effort reads the requested daily metric');
select is((select source from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','rest',current_date)),'whoop','Source is preserved');
select is((select count(*) from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','rest',current_date-1)),0::bigint,'Today scores never appear in yesterday rankings');
select is((select count(*) from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000002','rest',current_date)),0::bigint,'Consent remains per group');
select throws_ok($$select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',101,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now())))$$,'23514',null,'Reject scores outside the shared scale');
select throws_ok($$select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',80,'recharge',60,'rest',100,'effort_source','manual','recharge_source','whoop','rest_source','whoop','observed_at',now())))$$,'23514',null,'Reject unapproved sources');
select throws_ok($$select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date-9,'effort',80,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now())))$$,'P0001','Score day is out of range','Reject stale score days');
select throws_ok($$select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',80,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now()+interval '1 day')))$$,'P0001','Score observation is out of range','Reject future observations');
select throws_ok($$select * from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','streak',current_date)$$,'P0001','Unknown leaderboard metric','Old metrics cannot leak into new rankings');
select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',20,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now()-interval '1 hour')));
select is((select score from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date)),80,'Older device snapshots cannot replace fresher scores');
select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',0,'effort_source','appleHealth','observed_at',now())));
select is((select score from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date)),0,'A recorded zero remains ranked');
select is((select count(*) from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','recharge',current_date)),0::bigint,'An absent recovery signal clears the prior score instead of becoming zero');
select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',80,'recharge',60,'rest',100,'effort_source','whoop','recharge_source','whoop','rest_source','whoop','observed_at',now())));
select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000002',true);
select throws_ok($$select * from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date)$$,'P0001','Join this group to see its leaderboard','Invitation alone cannot read scores');
select public.answer_group_invite('b6140000-0000-4000-8000-000000000001',true);
select public.set_group_wellness_sharing('b6140000-0000-4000-8000-000000000001',true);
select public.publish_group_wellness(jsonb_build_array(jsonb_build_object('day',current_date,'effort',80,'recharge',60,'rest',100,'effort_source','fitbit','recharge_source','fitbit','rest_source','fitbit','observed_at',now())));
select is((select count(*) from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date) where rank_position=1),2::bigint,'Equal scores from different providers share a rank');
select is((select count(*) from public.group_wellness_daily),1::bigint,'Raw score rows remain account scoped');
select public.set_group_wellness_sharing('b6140000-0000-4000-8000-000000000001',false);
select is((select count(*) from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date)),1::bigint,'Revocation immediately removes a person from the leaderboard');
select set_config('request.jwt.claim.sub','a6140000-0000-4000-8000-000000000003',true);
select throws_ok($$select * from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','effort',current_date)$$,'P0001','Join this group to see its leaderboard','Outsiders cannot compare group scores');
select ok(not has_table_privilege('authenticated','public.group_wellness_daily','TRUNCATE'),'Clients cannot truncate health scores');
select ok(not has_table_privilege('authenticated','public.group_wellness_daily','INSERT'),'Clients cannot insert scores for other users');
reset role;
set local role anon;
select throws_ok($$select * from public.group_wellness_leaderboard('b6140000-0000-4000-8000-000000000001','rest',current_date)$$,'42501',null,'Anonymous users cannot execute leaderboard functions');
reset role;
select * from finish();
rollback;
