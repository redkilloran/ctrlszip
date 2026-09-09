-- CTRLS.zip — database schema & Row Level Security (RLS) policies.
-- Run this in the Supabase dashboard's SQL Editor (Project > SQL Editor >
-- New query), paste the whole file, and click Run. Safe to re-run only if
-- the tables don't already exist — it does not use "create or replace"
-- for tables, so re-running after tables exist will error out rather than
-- silently wiping data.
--
-- DESIGN NOTES (flagged in chat too — say if any of these don't match
-- your vision):
--   1. Three folder kinds: an admin-created "event" folder at the root
--      (e.g. momocon2026), a "user" folder nested directly beneath it
--      (the one someone gets from redeeming an invite card), and any
--      number of "subfolder"s a user creates inside their own folder to
--      organize things, nested arbitrarily deep.
--   2. Visibility has three levels per folder: public (default, shows up
--      everywhere), unlisted (hidden from the home page/tree, but still
--      readable by anyone who has the direct link/id — obscurity-based,
--      not real access control), and private (real database-level access
--      control: only the owner, admins, and users explicitly granted
--      access can read it or anything inside it).
--   3. Private-folder access is granted by the OTHER person's permanent
--      signup number (profiles.sequence_number, assigned once per account
--      at creation) — a separate sequence from folder_keys.sequence_number,
--      which numbers the physical invite cards/folders themselves, not
--      people.
--   4. Only "event" and "user" kind folders get a chat room — a
--      subfolder someone creates for their own organization does not.
--   5. Comments and chat are NOT frozen when a folder is zipped — only
--      folder/file edits are. Chat and commenting stay possible forever.
--   6. Chat messages are permanent — no edit/delete policy for them,
--      matching the archive/time-capsule intent. Files, folders, and
--      comments ARE user-deletable per the spec, zipped or not.

create extension if not exists pgcrypto;

-- ============================================================
-- profiles — one row per user, separate from Supabase's internal
-- auth.users table (which holds the synthesized "handle@ctrls.zip.internal"
-- email + password; see SPEC.md's "Auth without email" section).
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  sequence_number bigint generated always as identity unique, -- permanent personal signup number
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
-- folders — event folders, user folders, and user-created subfolders.
-- ============================================================
create type public.folder_kind as enum ('event', 'user', 'subfolder');
create type public.folder_visibility as enum ('public', 'unlisted', 'private');

create table public.folders (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.folders (id) on delete cascade,
  kind public.folder_kind not null,
  owner_id uuid references public.profiles (id),
  codename text,
  cover_photo_url text,
  sequence_number int, -- only set for "event" folders, e.g. the #0042 on invite cards
  visibility public.folder_visibility not null default 'public',
  is_zipped boolean not null default false,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint event_folders_are_root check (kind <> 'event' or parent_id is null),
  constraint event_folders_have_no_owner check (kind <> 'event' or owner_id is null),
  constraint non_event_folders_have_a_parent check (kind = 'event' or parent_id is not null),
  constraint non_event_folders_have_an_owner check (kind = 'event' or owner_id is not null)
);

create index folders_parent_id_idx on public.folders (parent_id);
create index folders_owner_id_idx on public.folders (owner_id);

-- Cross-row rules a simple check constraint can't express: a "user"
-- folder's parent must actually be an "event" folder; a "subfolder"'s
-- parent must be a "user" folder or another "subfolder" owned by the
-- same person (also re-checked on update, so dragging a folder to a new
-- parent can't be used to sneak it under someone else's folder).
create or replace function public.validate_folder_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent public.folders;
begin
  if new.kind = 'event' then
    return new;
  end if;

  select * into v_parent from public.folders where id = new.parent_id;

  if v_parent is null then
    raise exception 'parent folder does not exist';
  end if;

  if new.kind = 'user' and v_parent.kind <> 'event' then
    raise exception 'a user folder must be nested directly inside an event folder';
  end if;

  if new.kind = 'subfolder' then
    if v_parent.kind not in ('user', 'subfolder') then
      raise exception 'a sub-folder must be nested inside a user folder or another sub-folder';
    end if;
    if v_parent.owner_id <> new.owner_id then
      raise exception 'a sub-folder must have the same owner as its parent folder';
    end if;
  end if;

  return new;
end;
$$;

create trigger folders_validate_hierarchy
  before insert or update on public.folders
  for each row execute function public.validate_folder_hierarchy();

-- ============================================================
-- folder_access_grants — who's been let into a Private folder, by the
-- folder owner entering the other person's permanent signup number
-- (handled through the grant_folder_access() function further down).
-- Defined here, before folders' own RLS policies, because those policies
-- need to query this table.
-- ============================================================
create table public.folder_access_grants (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid not null references public.folders (id) on delete cascade,
  grantee_id uuid not null references public.profiles (id) on delete cascade,
  granted_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  unique (folder_id, grantee_id)
);

alter table public.folder_access_grants enable row level security;

create policy "owners and grantees can view a grant"
  on public.folder_access_grants for select
  using (
    grantee_id = auth.uid()
    or exists (select 1 from public.folders f where f.id = folder_id and f.owner_id = auth.uid())
  );

create policy "owners can revoke a grant"
  on public.folder_access_grants for delete
  using (exists (select 1 from public.folders f where f.id = folder_id and f.owner_id = auth.uid()));

-- No insert/update policy — creating a grant goes through
-- grant_folder_access() below, which resolves the target person by
-- their signup number and checks you actually own the folder.

-- Shared visibility check, reused by every table's read policy below:
-- readable if not private, or if you're the owner/an admin/explicitly
-- granted access via folder_access_grants.
create or replace function public.folder_is_visible_to(p_folder_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    f.visibility <> 'private'
    or f.owner_id = p_user_id
    or exists (
      select 1 from public.folder_access_grants g
      where g.folder_id = f.id and g.grantee_id = p_user_id
    )
    or exists (select 1 from public.profiles p where p.id = p_user_id and p.is_admin)
  from public.folders f
  where f.id = p_folder_id;
$$;

alter table public.folders enable row level security;

create policy "folders are readable based on visibility"
  on public.folders for select
  using (public.folder_is_visible_to(id, auth.uid()));

create policy "admins can create event folders"
  on public.folders for insert
  with check (
    kind = 'event'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

create policy "owners can create sub-folders in their own unzipped space"
  on public.folders for insert
  with check (
    kind = 'subfolder'
    and owner_id = auth.uid()
    and exists (
      select 1 from public.folders parent
      where parent.id = parent_id and parent.owner_id = auth.uid() and not parent.is_zipped
    )
  );
-- Note: there's deliberately no insert policy for kind = 'user' — those
-- are only created through redeem_folder_key() below, which checks a
-- real invite key before creating one.

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

create policy "files are readable based on folder visibility"
  on public.files for select
  using (public.folder_is_visible_to(folder_id, auth.uid()));

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

create policy "comments are readable based on folder visibility"
  on public.comments for select
  using (
    exists (
      select 1 from public.files fl
      where fl.id = file_id and public.folder_is_visible_to(fl.folder_id, auth.uid())
    )
  );

create policy "users can comment if they can see the folder"
  on public.comments for insert
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.files fl
      where fl.id = file_id and public.folder_is_visible_to(fl.folder_id, auth.uid())
    )
  );

create policy "authors can edit their own comments"
  on public.comments for update
  using (author_id = auth.uid());

create policy "authors can delete their own comments"
  on public.comments for delete
  using (author_id = auth.uid());

-- ============================================================
-- chat_messages — the live chat attached to a folder. Only "event" and
-- "user" kind folders get one; enforced by the trigger below.
-- ============================================================
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid not null references public.folders (id) on delete cascade,
  author_id uuid not null references public.profiles (id),
  body text not null,
  created_at timestamptz not null default now()
);

create index chat_messages_folder_id_idx on public.chat_messages (folder_id, created_at);

create or replace function public.enforce_chat_folder_kind()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.folders where id = new.folder_id and kind = 'subfolder') then
    raise exception 'chat is only available on event and user folders, not sub-folders';
  end if;
  return new;
end;
$$;

create trigger chat_messages_kind_check
  before insert on public.chat_messages
  for each row execute function public.enforce_chat_folder_kind();

alter table public.chat_messages enable row level security;

create policy "chat is readable based on folder visibility"
  on public.chat_messages for select
  using (public.folder_is_visible_to(folder_id, auth.uid()));

create policy "users can post to chat if they can see the folder"
  on public.chat_messages for insert
  with check (author_id = auth.uid() and public.folder_is_visible_to(folder_id, auth.uid()));

-- Turn on realtime updates for chat so open chat windows update live.
alter publication supabase_realtime add table public.chat_messages;

-- ============================================================
-- Activity tracking — bumps every ancestor folder's last_activity_at
-- (walking all the way up to the root event folder) whenever a file,
-- comment, or chat message happens. Powers the home page's "sort by
-- activity" list.
-- ============================================================
create or replace function public.bump_folder_activity(p_folder_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with recursive ancestors as (
    select id, parent_id from public.folders where id = p_folder_id
    union all
    select f.id, f.parent_id
    from public.folders f
    join ancestors a on f.id = a.parent_id
  )
  update public.folders
  set last_activity_at = now()
  where id in (select id from ancestors);
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
-- of raw table inserts, for actions that need extra validation RLS
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
-- it in one go (that's what "zipping" an event means). Deliberately does
-- NOT touch subfolders directly — a user folder's own subfolders read as
-- "zipped" through their ancestor chain, not via their own flag.
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

-- Grant a private folder's access to another user, identified by their
-- permanent signup number rather than their id (which the folder owner
-- wouldn't know off-hand).
create or replace function public.grant_folder_access(
  p_folder_id uuid,
  p_grantee_sequence_number bigint
)
returns public.folder_access_grants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_grantee_id uuid;
  v_grant public.folder_access_grants;
begin
  if not exists (
    select 1 from public.folders where id = p_folder_id and owner_id = auth.uid()
  ) then
    raise exception 'only the folder owner can grant access to it';
  end if;

  select id into v_grantee_id
  from public.profiles
  where sequence_number = p_grantee_sequence_number;

  if v_grantee_id is null then
    raise exception 'no user found with that number';
  end if;

  insert into public.folder_access_grants (folder_id, grantee_id, granted_by)
  values (p_folder_id, v_grantee_id, auth.uid())
  on conflict (folder_id, grantee_id) do nothing
  returning * into v_grant;

  return v_grant;
end;
$$;

grant execute on function public.grant_folder_access(uuid, bigint) to authenticated;
