-- A branch unlinked by hand stays unlinked. Without this, the next read on
-- any member's phone would link the feature to the branch named for it
-- again. True until someone unlinks; linking by hand sets it back.
alter table public.project_features
  add column auto_link boolean not null default true;
