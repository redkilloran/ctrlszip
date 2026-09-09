-- CTRLS.zip — role grants.
-- Run this AFTER 01_schema.sql and 02_media_storage.sql.
--
-- Tables created by hand in the Supabase Table Editor automatically get
-- default privileges for the "anon" and "authenticated" roles. Tables
-- created via raw SQL (like 01_schema.sql) don't — so even though the RLS
-- policies already written would allow an operation, the role never gets
-- far enough to reach that check, and Postgres rejects it up front with
-- "permission denied for table ...". This file grants the table-level
-- privileges; the RLS policies from 01_schema.sql still do the real,
-- per-row restricting on top of it.

grant usage on schema public to anon, authenticated;

-- Anyone (including logged-out visitors) can read anything RLS lets
-- through — public/unlisted folders and their contents, all profiles.
grant select on
  public.profiles,
  public.folders,
  public.files,
  public.comments,
  public.chat_messages
to anon, authenticated;

-- Only logged-in users write anything. (Granting these to anon too
-- wouldn't actually be exploitable, since every insert/update/delete
-- policy requires auth.uid() to match an owner — but there's no reason
-- to hand out privileges a logged-out visitor could never use.)
grant insert, update, delete on
  public.profiles,
  public.folders,
  public.files,
  public.comments,
  public.chat_messages
to authenticated;

-- folder_keys (invite codes) and folder_access_grants (Private folder
-- invites) have no logged-out use at all — RLS already restricts these
-- to admins/owners/grantees, this just lets authenticated requests reach
-- that check.
grant select, insert, update, delete on
  public.folder_keys,
  public.folder_access_grants
to authenticated;

-- profiles.sequence_number is a GENERATED ALWAYS AS IDENTITY column,
-- which needs sequence privileges to advance on insert — same idea as
-- the classic "permission denied for sequence ..._id_seq" gotcha with
-- old-style serial columns.
grant usage, select on all sequences in schema public to anon, authenticated;
