-- Avatars stop being readable by the whole internet.
--
-- 20260828140000 created the bucket public and gave it a select policy of
-- `using (bucket_id = 'avatars')` with no role attached, which means the
-- anonymous role passed it too. Every face was readable by anyone holding or
-- guessing the URL, signed in or not. Nobody agreed to that when they picked
-- a photo.
--
-- The bucket becomes private and reads become signed-in-only. Deliberately
-- not owner-only: a friend list draws faces, and an owner-only policy would
-- force a signed URL per row per refresh, which is a round trip per face to
-- hide a picture someone put on a profile on purpose. Any signed-in user may
-- read any avatar.
--
-- This alters what is already live rather than inserting a fresh bucket,
-- because 20260828140000 has been applied to production and the objects
-- underneath it belong to real accounts.

update storage.buckets
   set public = false,
       -- The client only ever sends JPEG. Both pickers hand
       -- `jpegData(compressionQuality:)` to `ProfileClient.uploadAvatar`,
       -- which pins `Content-Type: image/jpeg` on the request. The other
       -- three types were never reachable from the app and were only ever a
       -- wider surface to upload through.
       allowed_mime_types = array['image/jpeg']
       -- file_size_limit stays at 5242880 on purpose. The app's downsizing is
       -- being corrected separately, and tightening the ceiling here would
       -- start silently rejecting uploads from installs still running the old
       -- code, with nothing on the screen to explain it.
 where id = 'avatars';

drop policy if exists "avatars are readable" on storage.objects;
drop policy if exists "avatars are readable by signed-in users" on storage.objects;
drop policy if exists "own avatar insert" on storage.objects;
drop policy if exists "own avatar update" on storage.objects;
drop policy if exists "own avatar delete" on storage.objects;

-- `to authenticated` is the whole change from the old read policy: the
-- anonymous role is out, everyone signed in is still in.
create policy "avatars are readable by signed-in users"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars');

-- One folder per account, named for the user id, which is what makes
-- ownership a string comparison rather than a lookup. The name is pinned as
-- well as the folder, so an account owns exactly one avatar object and cannot
-- park arbitrary files under its own prefix and serve them from a bucket
-- every signed-in user can read.
--
-- `(select auth.uid())` rather than a bare `auth.uid()`, matching
-- 20260811164841_initial_schema.sql: the subquery form is evaluated once per
-- statement instead of once per row.
create policy "own avatar insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name = (select auth.uid())::text || '/avatar.jpg'
  );

create policy "own avatar update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name = (select auth.uid())::text || '/avatar.jpg'
  );

create policy "own avatar delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
