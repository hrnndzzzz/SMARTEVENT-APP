-- SMARTEVENT schema migration 001
-- Apply this file to the existing Supabase/Postgres database before
-- deploying the department-scoped API. It is intentionally idempotent.
-- Existing rows are left with NULL department_id because their department
-- cannot be inferred safely; backfill those rows before enabling scoped use.

CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
    ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE categories
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id);

ALTER TABLE events
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
    ADD COLUMN IF NOT EXISTS school_year VARCHAR(9),
    ADD COLUMN IF NOT EXISTS semester VARCHAR(10),
    ADD COLUMN IF NOT EXISTS event_scope VARCHAR(20);

ALTER TABLE expenses
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id);

ALTER TABLE inventory
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id);

CREATE TABLE IF NOT EXISTS cite_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('officer', 'adviser', 'treasurer')),
    position VARCHAR(50),
    department_id UUID REFERENCES departments(id),
    claimed_by_user_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS otp_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    purpose VARCHAR(20) NOT NULL CHECK (
        purpose IN ('registration', 'initial_setup', 'password_reset')
    ),
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS event_proposal_letters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id),
    title VARCHAR(200) NOT NULL,
    document_url TEXT NOT NULL,
    submitted_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_department_id
    ON users(department_id);
CREATE INDEX IF NOT EXISTS idx_categories_department_id
    ON categories(department_id);
CREATE INDEX IF NOT EXISTS idx_events_department_id
    ON events(department_id);
CREATE INDEX IF NOT EXISTS ix_events_school_year_semester
    ON events(school_year, semester);
CREATE INDEX IF NOT EXISTS ix_events_scope
    ON events(event_scope);
CREATE INDEX IF NOT EXISTS idx_expenses_department_id
    ON expenses(department_id);
CREATE INDEX IF NOT EXISTS idx_inventory_department_id
    ON inventory(department_id);
CREATE INDEX IF NOT EXISTS idx_otp_tokens_user_purpose
    ON otp_tokens(user_id, purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_proposal_letters_event_id
    ON event_proposal_letters(event_id);
