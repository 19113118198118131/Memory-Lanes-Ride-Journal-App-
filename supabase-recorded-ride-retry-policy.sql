-- Durable recorded rides reuse the same object path on retry. Supabase
-- Storage upserts require INSERT, SELECT, and UPDATE permission together.
-- Every policy remains limited to the signed-in rider's UUID folder.

begin;

create policy "users read own gpx"
on storage.objects for select
to authenticated
using (
  bucket_id = 'gpx-files'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "users update own gpx"
on storage.objects for update
to authenticated
using (
  bucket_id = 'gpx-files'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'gpx-files'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

commit;
