-- Yatri roster: per-year photo + years-of-yatra count (drives the Swamy tag).
ALTER TABLE trip_members ADD COLUMN IF NOT EXISTS yatra_years INT;
ALTER TABLE trip_members ADD COLUMN IF NOT EXISTS photo_url TEXT;
