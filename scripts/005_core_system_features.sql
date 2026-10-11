-- Apply after 001-004. Existing academic years are never guessed from dates.
BEGIN;

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    kind VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    read_at TIMESTAMPTZ,
    email_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (email_status IN ('pending', 'sent', 'failed')),
    email_attempts INTEGER NOT NULL DEFAULT 0 CHECK (email_attempts >= 0),
    email_sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_notification_user_kind UNIQUE (user_id, kind)
);
CREATE INDEX IF NOT EXISTS ix_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS ix_notifications_pending_email ON notifications(created_at)
    WHERE email_status IN ('pending', 'failed');
-- These are private API-owned messages, not publicly readable Supabase rows.
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE events ADD COLUMN IF NOT EXISTS school_year VARCHAR(9);
ALTER TABLE events ADD COLUMN IF NOT EXISTS semester VARCHAR(10);
ALTER TABLE events ADD COLUMN IF NOT EXISTS event_scope VARCHAR(20);

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'events_academic_metadata_required'
                   AND conrelid = 'events'::regclass) THEN
        ALTER TABLE events ADD CONSTRAINT events_academic_metadata_required CHECK (
            school_year IS NOT NULL AND school_year ~ '^[0-9]{4}-[0-9]{4}$'
            AND CASE WHEN school_year ~ '^[0-9]{4}-[0-9]{4}$' THEN
                substring(school_year, 1, 4)::integer >= 1900
                AND substring(school_year, 6, 4)::integer = substring(school_year, 1, 4)::integer + 1
                ELSE FALSE END
            AND semester IS NOT NULL AND semester IN ('1st', '2nd', 'summer')
            AND event_scope IS NOT NULL AND event_scope IN ('departmental', 'organizational')
        ) NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_events_organization_school_year ON events(organization_id, school_year);
COMMIT;

-- NOT VALID preserves legacy rows but enforces the rule on inserts/updates.
-- First repair legacy records using actual academic records; then execute:
-- ALTER TABLE events VALIDATE CONSTRAINT events_academic_metadata_required;
-- ALTER TABLE events ALTER COLUMN school_year SET NOT NULL;
-- ALTER TABLE events ALTER COLUMN semester SET NOT NULL;
-- ALTER TABLE events ALTER COLUMN event_scope SET NOT NULL;
