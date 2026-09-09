-- CTRLS.zip — database schema & Row Level Security (RLS) policies.
-- Run this in the Supabase dashboard's SQL Editor (Project > SQL Editor >
-- New query), paste the whole file, and click Run. Safe to re-run only if
-- the tables don't already exist — it does not use "create or replace"
-- for tables, so re-running after tables exist will error out rather than
-- silently wiping data.
--
-- DESIGN ASSUMPTIONS baked into this draft (flagged in chat too — say if
-- any of these don't match your vision and we'll adjust before building
-- against this schema):
--   1. Two-level hierarchy only: an admin-created "event" folder (e.g.
--      momocon2026) at the root, with "user" folders nested directly
--      beneath it. Users don't create further sub-folders of their own —
--      files sit directly inside their one folder.
--   2. "Private" folders are unlisted, not access-controlled: the app's
--      home page and folder-tree queries filter out is_private = true,
--      but this schema does NOT block a direct row-level read of a
--      private folder for someone who already has its id/link (matching
--      "accessible only directly by link" from the spec). A technically
--      determined person poking at the API directly could still find
--      private folders by listing the table — this protects against
--      casual browsing, not against that.
--   3. Comments and chat are NOT frozen when a folder is zipped — only
--      folder/file edits are. Chat and commenting stay possible forever
--      (matches "chat rooms remain active" after zipping).
--   4. Chat messages are permanent — no edit/delete policy for them,
--      matching the archive/time-capsule intent. Files, folders, and
--      comments ARE user-deletable per the spec.

create extension if not exists pgcrypto;

-- ============================================================
-- profiles — one row per user, separate from Supabase's internal
-- auth.users table (which holds the synthesized "handle@ctrls.zip.internal"
-- email + password; see SPEC.md's "Auth without email" section).
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text unique not null check (handle ~ '^[a-z0-9_]{3,20}$'),
  pfp_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are publicly readable"
  on public.profiles for select
  using (true);

create policy "users can create their own profile"
  on public.profiles for insert
  with check (id = auth.uid());

create policy "users can update their own profile"
  on public.profiles for update
  using (id = auth.uid());

-- No delete policy on purpose — no account deletion, per spec.

-- ============================================================
-- folders — both the admin-created "event" folders and the "user"
-- folders nested inside them.
-- ============================================================
create type public.folder_kind as enum ('event', 'user');

create table public.folders (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.folders (id) on delete cascade,
  kind public.folder_kind not null,
  owner_id uuid references public.profiles (id),
  codename text,
  cover_photo_url text,
  sequence_number int,
  is_private boolean not null default false,
  is_zipped boolean not null default false,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint event_folders_are_root check (kind <> 'event' or parent_id is null),
  constraint event_folders_have_no_owner check (kind <> 'event' or owner_id is null),
  constraint user_folders_have_a_parent check (kind <> 'user' or parent_id is not null),
  constraint user_folders_have_an_owner check (kind <> 'user' or owner_id is not null)
);

create index folders_parent_id_idx on public.folders (parent_id);
create index folders_owner_id_idx on public.folders (owner_id);

alter table public.folders enable row level security;

create policy "folders are readable by anyone with the id or link"
  on public.folders for select
  using (true);

create policy "admins can create event folders"
  on public.folders for insert
  with check (
    kind = 'event'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );
-- Note: there's deliberately no general insert policy for kind = 'user' —
-- user folders are only created through redeem_folder_key() below, which
-- checks a real invite key before creating one.

create policy "owners can update their own unzipped folder"
  on public.folders for update
  using (owner_id = auth.uid() and not is_zipped)
  with check (owner_id = auth.uid());

create policy "admins can update any folder"
  on public.folders for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy "owners can delete their own folder anytime"
  on public.folders for delete
  using (owner_id = auth.uid());

create policy "admins can delete any folder"
  on public.folders for delete
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- ============================================================
-- folder_keys — the redemption codes printed on physical invite cards.
-- Kept locked down (admin-only reads) so codes can't be listed/guessed
-- via the API; redemption itself goes through redeem_folder_key().
-- ============================================================
create table public.folder_keys (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  sequence_number int not null unique,
  parent_folder_id uuid not null references public.folders (id) on delete cascade,
  claimed_by uuid references public.profiles (id),
  claimed_folder_id uuid references public.folders (id),
  created_at timestamptz not null default now(),
  claimed_at timestamptz
);

alter table public.folder_keys enable row level security;

create policy "admins can view folder keys"
  on public.folder_keys for select
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy "admins can create folder keys"
  on public.folder_keys for insert
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy "admins can update folder keys"
  on public.folder_keys for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- ============================================================
-- files — the "posts" (text/audio/image) inside a folder.
-- ============================================================
create type public.file_kind as enum ('text', 'audio', 'image');

create table public.files (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid not null references public.folders (id) on delete cascade,
  owner_id uuid not null references public.profiles (id),
  kind public.file_kind not null,
  title text,
  body text, -- markdown content, for kind = 'text'
  media_url text, -- Supabase Storage path, for kind = 'audio' | 'image'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint text_files_have_a_body check (kind <> 'text' or body is not null),
  constraint media_files_have_a_url check (kind = 'text' or media_url is not null)
);

create index files_folder_id_idx on public.files (folder_id);

alter table public.files enable row level security;

create policy "files are readable by anyone"
  on public.files for select
  using (true);

create policy "owners can add files to their own unzipped folder"
  on public.files for insert
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.folders f
      where f.id = folder_id and f.owner_id = auth.uid() and not f.is_zipped
    )
  );

create policy "owners can edit their own files in an unzipped folder"
  on public.files for update
  using (
    owner_id = auth.uid()
    and exists (select 1 from public.folders f where f.id = folder_id and not f.is_zipped)
  );

create policy "owners can delete their own files anytime"
  on public.files for delete
  using (owner_id = auth.uid());

-- ============================================================
-- comments — left on individual files.
-- ============================================================
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references public.files (id) on delete cascade,
  author_id uuid not null references public.profiles (id),
  body text not null,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create index comments_file_id_idx on public.comments (file_id);

alter table public.comments enable row level security;

create policy "comments are readable by anyone"
  on public.comments for select
  using (true);

create policy "logged-in users can comment"
  on public.comments for insert
  with check (author_id = auth.uid());

create policy "authors can edit their own comments"
  on public.comments for update
  using (author_id = auth.uid());

create policy "authors can delete their own comments"
  on public.comments for delete
  using (author_id = auth.uid());

-- ============================================================
-- chat_messages — the live chat attached to a folder (event or user).
-- ============================================================
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid not null references public.folders (id) on delete cascade,
  author_id uuid not null references public.profiles (id),
  body text not null,
  created_at timestamptz not null default now()
);

create index chat_messages_folder_id_idx on public.chat_messages (folder_id, created_at);

alter table public.chat_messages enable row level security;

create policy "chat is readable by anyone"
  on public.chat_messages for select
  using (true);

create policy "logged-in users can post to chat"
  on public.chat_messages for insert
  with check (author_id = auth.uid());

-- Turn on realtime updates for chat so open chat windows update live.
alter publication supabase_realtime add table public.chat_messages;

-- ============================================================
-- Activity tracking — bumps a folder's last_activity_at (and its parent
-- event folder's, one level up) whenever a file, comment, or chat message
-- happens inside it. Powers the home page's "sort by activity" list.
-- ============================================================
create or replace function public.bump_folder_activity(p_folder_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.folders
  set last_activity_at = now()
  where id = p_folder_id
     or id = (select parent_id from public.folders where id = p_folder_id);
end;
$$;

create or replace function public.on_file_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bump_folder_activity(coalesce(new.folder_id, old.folder_id));
  return coalesce(new, old);
end;
$$;

create trigger files_bump_activity
  after insert or update or delete on public.files
  for each row execute function public.on_file_activity();

create or replace function public.on_comment_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_folder_id uuid;
begin
  select folder_id into v_folder_id
  from public.files
  where id = coalesce(new.file_id, old.file_id);

  perform public.bump_folder_activity(v_folder_id);
  return coalesce(new, old);
end;
$$;

create trigger comments_bump_activity
  after insert or update or delete on public.comments
  for each row execute function public.on_comment_activity();

create or replace function public.on_chat_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bump_folder_activity(new.folder_id);
  return new;
end;
$$;

create trigger chat_bump_activity
  after insert on public.chat_messages
  for each row execute function public.on_chat_activity();

-- ============================================================
-- Helper functions — called from the app via supabase.rpc(...) instead
-- of raw table inserts, for the actions that need extra validation RLS
-- alone can't express cleanly.
-- ============================================================

-- Redeem a folder key: validates the code, creates the user's folder
-- nested under the key's event folder, and marks the key claimed — all
-- in one transaction so two people can't redeem the same key at once.
create or replace function public.redeem_folder_key(
  p_code text,
  p_codename text,
  p_cover_photo_url text
)
returns public.folders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key public.folder_keys;
  v_folder public.folders;
begin
  if auth.uid() is null then
    raise exception 'must be logged in to redeem a folder key';
  end if;

  select * into v_key
  from public.folder_keys
  where code = p_code
  for update;

  if v_key is null then
    raise exception 'invalid folder key';
  end if;

  if v_key.claimed_by is not null then
    raise exception 'this folder key has already been claimed';
  end if;

  insert into public.folders (parent_id, kind, owner_id, codename, cover_photo_url)
  values (v_key.parent_folder_id, 'user', auth.uid(), p_codename, p_cover_photo_url)
  returning * into v_folder;

  update public.folder_keys
  set claimed_by = auth.uid(),
      claimed_folder_id = v_folder.id,
      claimed_at = now()
  where id = v_key.id;

  return v_folder;
end;
$$;

grant execute on function public.redeem_folder_key(text, text, text) to authenticated;

-- Dev portal: generate a new folder key for a given event folder. Auto
-- picks the next sequence number and a random 8-character code.
create or replace function public.create_folder_key(p_parent_folder_id uuid)
returns public.folder_keys
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key public.folder_keys;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'only admins can create folder keys';
  end if;

  insert into public.folder_keys (code, sequence_number, parent_folder_id)
  values (
    upper(substr(md5(random()::text), 1, 8)),
    coalesce((select max(sequence_number) from public.folder_keys), 0) + 1,
    p_parent_folder_id
  )
  returning * into v_key;

  return v_key;
end;
$$;

grant execute on function public.create_folder_key(uuid) to authenticated;

-- Dev portal: freeze an event folder AND every user folder nested inside
-- it in one go (that's what "zipping" an event means).
create or replace function public.zip_event_folder(p_folder_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'only admins can zip a folder';
  end if;

  update public.folders
  set is_zipped = true
  where id = p_folder_id or parent_id = p_folder_id;
end;
$$;

grant execute on function public.zip_event_folder(uuid) to authenticated;
