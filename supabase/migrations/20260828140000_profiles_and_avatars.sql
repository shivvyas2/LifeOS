-- The profile becomes server data, and the avatar becomes a stored object.
--
-- Both were on the device. Profile fields lived in `auth.users.user_metadata`
-- with a copy in UserDefaults, and the avatar was a JPEG in the app's support
-- directory. Neither followed the account: signing in on a second phone, or as
-- a second account on the same phone, produced a profile with no name and no
-- picture, and in the multi-account case the local copies were not even keyed
-- by account, so one person's name and photo were shown to another.
--
-- `profiles` already existed for friend search, holding a display name and
-- nothing else. It is the natural home for the rest.

alter table public.profiles
  add column if not exists first_name  text,
  add column if not exists last_name   text,
  add column if not exists country     text,
  -- A birthday has no clock. Storing a timestamp would move it by a day
  -- across time zones, which is a bug nobody reports and everybody notices.
  add column if not exists birth_date  date,
  add column if not exists height_cm   double precision,
  -- 'woman' | 'man' | 'non_binary'. Null is "prefer not to say", which is a
  -- real answer and the default, so it must stay representable.
  add column if not exists gender      text,
  -- The object's path inside the avatars bucket, not a URL. A URL would bake
  -- in the project host and the signing scheme, both of which outlive their
  -- correctness.
  add column if not exists avatar_path text;

-- Search reads this table, and it is readable by every signed-in user, so it
-- must stay the case that nothing here is private beyond what a person put on
-- a profile on purpose. The columns above are the ones the app already asked
-- for at signup and shows back on the profile screen.

-- Avatars. Public read, because a friend list shows faces and a signed URL per
-- row per refresh is a great deal of work to hide a picture someone chose to
-- put on a profile. Writes are restricted to the owner by path.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', true, 5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- One folder per account, named for the user id, which is what makes the
-- ownership check below a string comparison rather than a lookup.
create policy "avatars are readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "own avatar insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own avatar update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own avatar delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
