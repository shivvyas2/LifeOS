-- Answering a request is the only thing an update to a friendship can be.
-- The RLS policy gates WHICH rows the addressee may touch; these grants gate
-- WHICH COLUMNS any authenticated update may touch, so the same statement
-- that accepts a request can never smuggle in a new requester or a new
-- timestamp. Postgres enforces column grants before policies even run.
revoke update on table public.friendships from authenticated;
grant update (status) on table public.friendships to authenticated;
