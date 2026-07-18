-- Swamy Sharanam Phase 1 schema
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE member_role AS ENUM ('leader', 'volunteer', 'swamy');
CREATE TYPE count_session_status AS ENUM ('open', 'closed');
CREATE TYPE count_mark_status AS ENUM ('present', 'missing', 'excused');
CREATE TYPE count_mark_source AS ENUM ('self', 'helper');
CREATE TYPE announcement_priority AS ENUM ('info', 'urgent');
CREATE TYPE count_scope_kind AS ENUM ('all', 'bus');

CREATE TABLE trips (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    year            INT NOT NULL,
    starts_on       DATE NOT NULL,
    ends_on         DATE NOT NULL,
    helpers_may_start_count BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164      TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE trip_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            member_role NOT NULL DEFAULT 'swamy',
    is_kanni        BOOLEAN NOT NULL DEFAULT FALSE,
    is_senior       BOOLEAN NOT NULL DEFAULT FALSE,
    emergency_phone TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (trip_id, user_id)
);

CREATE INDEX idx_trip_members_trip ON trip_members(trip_id);

CREATE TABLE otp_challenges (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164      TEXT NOT NULL,
    code_hash       TEXT NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    consumed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_phone ON otp_challenges(phone_e164);

CREATE TABLE itinerary_stops (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    day_date        DATE NOT NULL,
    starts_at       TIMESTAMPTZ,
    title           TEXT NOT NULL,
    place_name      TEXT,
    notes           TEXT,
    map_url         TEXT,
    lost_person_tip TEXT,
    sort_order      INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_itinerary_trip ON itinerary_stops(trip_id, day_date, sort_order);

CREATE TABLE vehicles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    label           TEXT NOT NULL,
    vehicle_type    TEXT NOT NULL DEFAULT 'bus',
    capacity        INT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE rooms (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    hotel_name      TEXT NOT NULL,
    room_label      TEXT NOT NULL,
    capacity        INT,
    night_date      DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE train_berths (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    train_number    TEXT NOT NULL,
    train_name      TEXT,
    coach           TEXT NOT NULL,
    berth           TEXT,
    direction       TEXT NOT NULL DEFAULT 'outbound',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE assignments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    vehicle_id      UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    seat_label      TEXT,
    room_id         UUID REFERENCES rooms(id) ON DELETE SET NULL,
    train_berth_id  UUID REFERENCES train_berths(id) ON DELETE SET NULL,
    published_at    TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (trip_id, member_id)
);

CREATE TABLE count_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    checkpoint_label TEXT NOT NULL,
    scope_kind      count_scope_kind NOT NULL DEFAULT 'all',
    scope_vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    status          count_session_status NOT NULL DEFAULT 'open',
    expected_count  INT NOT NULL DEFAULT 0,
    started_by      UUID NOT NULL REFERENCES trip_members(id),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_by       UUID REFERENCES trip_members(id),
    closed_at       TIMESTAMPTZ,
    ready_to_march_note TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_one_open_count_per_trip
    ON count_sessions(trip_id)
    WHERE status = 'open';

CREATE INDEX idx_count_sessions_trip ON count_sessions(trip_id, started_at DESC);

CREATE TABLE count_marks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES count_sessions(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    status          count_mark_status NOT NULL,
    source          count_mark_source NOT NULL,
    marked_by       UUID NOT NULL REFERENCES trip_members(id),
    marked_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    client_id       TEXT,
    UNIQUE (session_id, member_id)
);

CREATE INDEX idx_count_marks_session ON count_marks(session_id, status);

CREATE TABLE announcements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    author_id       UUID NOT NULL REFERENCES trip_members(id),
    priority        announcement_priority NOT NULL DEFAULT 'info',
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    count_session_id UUID REFERENCES count_sessions(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_announcements_trip ON announcements(trip_id, created_at DESC);

CREATE TABLE expenses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    paid_by_member_id UUID NOT NULL REFERENCES trip_members(id),
    amount_paise    BIGINT NOT NULL CHECK (amount_paise > 0),
    currency        TEXT NOT NULL DEFAULT 'INR',
    category        TEXT,
    note            TEXT,
    spent_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID NOT NULL REFERENCES trip_members(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE expense_shares (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_id      UUID NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    share_paise     BIGINT NOT NULL CHECK (share_paise >= 0),
    UNIQUE (expense_id, member_id)
);

CREATE TABLE audit_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID,
    actor_member_id UUID,
    action          TEXT NOT NULL,
    entity_type     TEXT NOT NULL,
    entity_id       UUID,
    payload_json    JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE knowledge_chunks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    source_title    TEXT NOT NULL,
    source_section  TEXT,
    content         TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_knowledge_trip ON knowledge_chunks(trip_id);
