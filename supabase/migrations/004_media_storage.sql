-- Alkazemi Asset Management · 004 · file storage
-- Photos, videos and documents (tickets, building photos, licences, inspections) go to the public bucket aqar-media.
insert into storage.buckets (id, name, public, file_size_limit)
values ('aqar-media', 'aqar-media', true, 52428800)
on conflict (id) do update set public = true;

drop policy if exists "aqar media read" on storage.objects;
drop policy if exists "aqar media upload" on storage.objects;
create policy "aqar media read" on storage.objects for select to anon, authenticated using (bucket_id = 'aqar-media');
create policy "aqar media upload" on storage.objects for insert to anon, authenticated with check (bucket_id = 'aqar-media');
