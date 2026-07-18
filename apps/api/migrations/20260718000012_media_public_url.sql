-- Persist the public (S3/CloudFront) URL alongside the storage key. Populated
-- for the S3 backend so the media file lives only in S3 and the app reads the
-- stored URL directly. Left NULL for the local dev backend, where the read URL
-- is a short-lived signed path derived at request time.
ALTER TABLE media_assets ADD COLUMN public_url TEXT;
