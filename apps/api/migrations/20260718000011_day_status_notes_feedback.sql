-- Excused / not-traveling for honest expected counts
CREATE TABLE trip_member_day_status (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    day_date        DATE NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('traveling', 'not_traveling')),
    note            TEXT,
    set_by          UUID REFERENCES trip_members(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (member_id, day_date)
);

CREATE INDEX idx_day_status_trip_day ON trip_member_day_status(trip_id, day_date);

-- Phase 2: simple group notes per day
CREATE TABLE day_notes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    day_date        DATE NOT NULL,
    author_id       UUID NOT NULL REFERENCES trip_members(id),
    body            TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_day_notes_trip_day ON day_notes(trip_id, day_date);

-- Phase 2: mala-removal reminders
CREATE TABLE mala_reminders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    remind_on       DATE NOT NULL,
    created_by      UUID REFERENCES trip_members(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mala_reminders_trip ON mala_reminders(trip_id, remind_on);

-- Phase 2: post-trip feedback / lessons
CREATE TABLE trip_feedback (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES trip_members(id) ON DELETE CASCADE,
    rating          INT CHECK (rating BETWEEN 1 AND 5),
    lessons         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (trip_id, member_id)
);

-- Phase 3: registration interest for next season
CREATE TABLE registration_interest (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id         UUID REFERENCES trips(id) ON DELETE SET NULL,
    year_interest   INT NOT NULL,
    phone_e164      TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reg_interest_year ON registration_interest(year_interest);
