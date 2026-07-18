CREATE TYPE food_session_status AS ENUM ('open', 'closed');
CREATE TYPE food_scope_kind AS ENUM ('all', 'bus');

CREATE TABLE food_sessions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id          UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    label            TEXT NOT NULL,
    scope_kind       food_scope_kind NOT NULL DEFAULT 'all',
    scope_vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    status           food_session_status NOT NULL DEFAULT 'open',
    expected_count   INT NOT NULL DEFAULT 0,
    started_by       UUID NOT NULL REFERENCES trip_members(id),
    started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_by        UUID REFERENCES trip_members(id),
    closed_at        TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_one_open_food_per_trip
    ON food_sessions(trip_id)
    WHERE status = 'open';

CREATE TABLE food_marks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID NOT NULL REFERENCES food_sessions(id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    received    BOOLEAN NOT NULL DEFAULT TRUE,
    marked_by   UUID NOT NULL REFERENCES trip_members(id),
    marked_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, member_id)
);

CREATE INDEX idx_food_marks_session ON food_marks(session_id);

CREATE TABLE packing_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id       UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    title         TEXT NOT NULL,
    quantity_hint TEXT,
    sort_order    INT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_packing_items_trip ON packing_items(trip_id, sort_order);

CREATE TABLE packing_checks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id     UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    item_id     UUID NOT NULL REFERENCES packing_items(id) ON DELETE CASCADE,
    checked     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (member_id, item_id)
);
