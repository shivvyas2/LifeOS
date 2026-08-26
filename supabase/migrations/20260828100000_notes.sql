-- PARA notes.
--
-- Follows the rules the initial schema set: RLS on every table, every policy
-- scoped to auth.uid(), and a touch trigger so a client cannot advance
-- updated_at past the server's clock and win a conflict it should have lost.
--
-- The local SwiftData store stays the source of truth for the UI. These two
-- tables are the sync target, so both carry the tombstone column the client
-- writes on delete: a row deleted on one device has to be representable as a
-- fact the other device can pull, not as an absence it cannot observe.

create table public.note_folders (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  name text not null,
  icon text not null default '',
  -- 'projects' | 'areas' | 'research' | 'archive'. Deliberately not an enum:
  -- a shelf added later should land as data, not as a failed insert against a
  -- type the old clients do not know about.
  bucket text not null,
  accent text not null default 'sage',
  -- Self-referencing, and intentionally not a foreign key. Rows arrive in
  -- whatever order the client batches them, so a child can reach the server
  -- before its parent; a constraint here would reject valid syncs for a
  -- condition that resolves itself milliseconds later.
  parent_id uuid,
  sort_order integer not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.note_documents (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  title text not null default '',
  icon text not null default '',
  -- 'note' | 'journal' | 'task'
  kind text not null default 'note',
  bucket text not null default 'projects',
  accent text not null default 'sage',
  folder_id uuid,

  -- The block array, exactly as the editor holds it. jsonb rather than text so
  -- a future server-side reader can query into it without parsing, and so a
  -- malformed document is rejected at write time rather than discovered on a
  -- device six weeks later.
  blocks jsonb not null default '[]'::jsonb,

  -- A PencilKit drawing, base64 encoded. Null for the overwhelming majority of
  -- pages, which is why it is a column here rather than a storage object: a
  -- separate bucket would cost a second round trip on every page that has ink
  -- and a second failure mode on every page that does not.
  drawing text,

  -- The day a journal entry is about, which is not always the day it was
  -- written. date, not timestamptz, for the reason daily_metrics gives: a
  -- device in another timezone must not silently write the adjacent day.
  entry_date date,
  due_date timestamptz,
  -- 'todo' | 'inProgress' | 'done' | 'blocked' | 'scheduled'
  status text not null default 'todo',

  sort_order integer not null default 0,
  is_favorite boolean not null default false,
  opened_at timestamptz,
  archived_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index note_folders_user_updated_idx on public.note_folders (user_id, updated_at);
create index note_documents_user_updated_idx on public.note_documents (user_id, updated_at);
create index note_documents_user_bucket_idx on public.note_documents (user_id, bucket, updated_at desc);
-- The archive shelf and the journal list are the two reads that are not
-- "everything changed since": both are narrow, and both would otherwise scan
-- every page the person owns.
create index note_documents_user_archived_idx on public.note_documents (user_id, archived_at)
  where archived_at is not null;
create index note_documents_user_journal_idx on public.note_documents (user_id, entry_date desc)
  where entry_date is not null;

create trigger note_folders_touch
  before update on public.note_folders
  for each row execute function public.touch_updated_at();

create trigger note_documents_touch
  before update on public.note_documents
  for each row execute function public.touch_updated_at();

alter table public.note_folders enable row level security;
alter table public.note_documents enable row level security;

create policy "own note folders" on public.note_folders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own note documents" on public.note_documents
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
