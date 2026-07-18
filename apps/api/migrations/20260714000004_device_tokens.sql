CREATE TABLE IF NOT EXISTS device_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id   UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    trip_id     UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    fcm_token   TEXT NOT NULL UNIQUE,
    platform    TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_trip ON device_tokens(trip_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_member ON device_tokens(member_id);
