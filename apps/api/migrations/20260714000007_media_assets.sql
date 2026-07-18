CREATE TABLE media_assets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    uploader_id     UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    caption         TEXT,
    storage_key     TEXT NOT NULL,
    content_type    TEXT NOT NULL DEFAULT 'image/jpeg',
    byte_size       BIGINT NOT NULL DEFAULT 0,
    approved        BOOLEAN NOT NULL DEFAULT FALSE,
    approved_by     UUID REFERENCES trip_members(id),
    approved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_media_trip_approved ON media_assets(trip_id, approved, created_at DESC);
CREATE INDEX idx_media_uploader ON media_assets(uploader_id);
