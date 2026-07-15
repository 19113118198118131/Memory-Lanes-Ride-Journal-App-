-- Memory Lanes offline road-pack distribution.
--
-- Graph packs contain public OpenStreetMap-derived road data and no rider data.
-- Downloads are public and CDN-cacheable. Uploads remain restricted to the
-- dashboard/service role; the iOS client receives no INSERT/UPDATE/DELETE policy.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'offline-regions',
  'offline-regions',
  true,
  536870912,
  array['application/octet-stream', 'application/json']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Public buckets bypass read access control for object retrieval. Deliberately
-- do not grant client upload policies: manifests and graph packs are release
-- artifacts published only by trusted build infrastructure.
