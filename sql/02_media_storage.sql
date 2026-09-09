-- CTRLS.zip — media storage bucket & policies.
-- Run this AFTER 01_schema.sql, in the same SQL Editor. Each numbered file
-- in sql/ is a one-time migration — run new ones as they're added, don't
-- re-run old ones once they've succeeded (they'll error on already-
-- existing objects rather than silently no-op).
--
-- One bucket, "media", holds every dithered image a user uploads —
-- profile pictures and folder cover photos for now, post images/audio
-- later. It's public (readable by anyone with the URL) since none of
-- that is tied to a Private folder's confidentiality — profiles are
-- always public, and folder cover photos are cosmetic. If Private-folder
-- post media needs real access control later, that'll want a second,
-- non-public bucket with policies mirroring folder_is_visible_to().
--
-- Path convention enforced below: every object must live under
-- "<uploader's user id>/...", e.g. "3f2a.../avatar.png" or
-- "3f2a.../cover-<folder id>.png" — that's what lets the policies check
-- "is this your own stuff" without needing a lookup table.

insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

create policy "media is publicly readable"
  on storage.objects for select
  using (bucket_id = 'media');

create policy "users can upload into their own media folder"
  on storage.objects for insert
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "users can update their own media"
  on storage.objects for update
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "users can delete their own media"
  on storage.objects for delete
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
