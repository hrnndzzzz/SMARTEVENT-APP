-- Phase 1. Apply as schema owner AFTER scripts/001 through 008.
-- Existing approved/completed events remain unchanged. Pending proposals now
-- require an administrator-configured institutional route before final approval.
BEGIN;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartevent_app') THEN
        RAISE EXCEPTION 'Apply scripts/008_security_hardening.sql before Phase 1';
    END IF;
END $$;

ALTER TABLE public.events ALTER COLUMN status TYPE VARCHAR(40);
ALTER TABLE public.events ADD COLUMN review_round INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.events ADD CONSTRAINT event_review_round_positive CHECK (review_round > 0);

-- Replace only role/status checks; retain unrelated historical constraints.
DO $$
DECLARE role_att SMALLINT; status_att SMALLINT; item RECORD;
BEGIN
    SELECT attnum INTO role_att FROM pg_attribute
        WHERE attrelid = 'public.users'::regclass AND attname = 'role';
    FOR item IN SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.users'::regclass AND contype = 'c'
            AND conkey = ARRAY[role_att]::smallint[]
    LOOP
        EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', item.conname);
    END LOOP;
    SELECT attnum INTO status_att FROM pg_attribute
        WHERE attrelid = 'public.events'::regclass AND attname = 'status';
    FOR item IN SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.events'::regclass AND contype = 'c'
            AND conkey = ARRAY[status_att]::smallint[]
    LOOP
        EXECUTE format('ALTER TABLE public.events DROP CONSTRAINT %I', item.conname);
    END LOOP;
END $$;

ALTER TABLE public.users ADD CONSTRAINT users_role_check CHECK (
    role IN ('super_admin', 'admin', 'adviser', 'treasurer', 'officer', 'sds_staff', 'signatory')
) NOT VALID;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_scope_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_scope_check CHECK (
    (role IN ('super_admin', 'sds_staff', 'signatory') AND department_id IS NULL AND organization_id IS NULL)
    OR (role IN ('admin', 'adviser', 'treasurer', 'officer') AND department_id IS NOT NULL AND organization_id IS NOT NULL)
) NOT VALID;
ALTER TABLE public.events ADD CONSTRAINT events_status_check CHECK (
    status IN ('draft', 'pending', 'pending_adviser', 'pending_admin',
        'pending_institutional_review', 'approved', 'rejected', 'completed')
) NOT VALID;

CREATE TABLE public.document_routing (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    review_round INTEGER NOT NULL DEFAULT 1,
    step_order INTEGER NOT NULL,
    signatory_id UUID NOT NULL REFERENCES public.users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    remarks TEXT,
    decided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_routing_event_round_step UNIQUE (event_id, review_round, step_order),
    CONSTRAINT uq_routing_event_round_signatory UNIQUE (event_id, review_round, signatory_id),
    CONSTRAINT routing_positive_order CHECK (review_round > 0 AND step_order > 0),
    CONSTRAINT routing_status_check CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT routing_decision_check CHECK (
        (status = 'pending' AND decided_at IS NULL) OR (status <> 'pending' AND decided_at IS NOT NULL)
    )
);
CREATE INDEX ix_document_routing_signatory_id ON public.document_routing (signatory_id);

CREATE TABLE public.requirement_presets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    phase VARCHAR(20) NOT NULL,
    requires_notarization BOOLEAN NOT NULL DEFAULT false,
    is_sensitive BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT preset_phase_check CHECK (phase IN ('pre_activity', 'post_activity'))
);

CREATE TABLE public.event_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    student_number VARCHAR(50) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_participant_event_student UNIQUE (event_id, student_number),
    CONSTRAINT uq_participant_id_event UNIQUE (id, event_id),
    CONSTRAINT participant_identity_check CHECK (length(trim(student_number)) > 0 AND length(trim(full_name)) > 0)
);

CREATE TABLE public.event_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    preset_id UUID REFERENCES public.requirement_presets(id),
    name VARCHAR(150) NOT NULL,
    description TEXT,
    phase VARCHAR(20) NOT NULL,
    is_required BOOLEAN NOT NULL DEFAULT true,
    requires_notarization BOOLEAN NOT NULL DEFAULT false,
    is_sensitive BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_requirement_id_event UNIQUE (id, event_id),
    CONSTRAINT uq_requirement_event_preset UNIQUE (event_id, preset_id),
    CONSTRAINT requirement_phase_check CHECK (phase IN ('pre_activity', 'post_activity')),
    CONSTRAINT requirement_name_check CHECK (length(trim(name)) > 0)
);
CREATE INDEX ix_event_requirements_event_id ON public.event_requirements (event_id);
CREATE INDEX ix_event_requirements_preset_id ON public.event_requirements (preset_id);

CREATE TABLE public.student_compliance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    participant_id UUID NOT NULL,
    requirement_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'MISSING',
    reviewed_by UUID REFERENCES public.users(id),
    reviewed_at TIMESTAMPTZ,
    remarks TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_compliance_participant_requirement UNIQUE (participant_id, requirement_id),
    CONSTRAINT compliance_participant_event_fk FOREIGN KEY (participant_id, event_id)
        REFERENCES public.event_participants (id, event_id),
    CONSTRAINT compliance_requirement_event_fk FOREIGN KEY (requirement_id, event_id)
        REFERENCES public.event_requirements (id, event_id),
    CONSTRAINT compliance_status_check CHECK (status IN ('MISSING', 'SUBMITTED', 'VERIFIED', 'REJECTED')),
    CONSTRAINT compliance_review_check CHECK (
        status NOT IN ('VERIFIED', 'REJECTED') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    )
);
CREATE INDEX ix_student_compliance_records_event_id ON public.student_compliance_records (event_id);
CREATE INDEX ix_student_compliance_records_requirement_id ON public.student_compliance_records (requirement_id);
CREATE INDEX ix_student_compliance_records_reviewed_by ON public.student_compliance_records (reviewed_by);

-- Presets requested in the plan; these are configurable document definitions,
-- not official CHED form replicas or automatic legal certification.
INSERT INTO public.requirement_presets (code, name, description, phase, requires_notarization, is_sensitive)
VALUES
    ('parent_guardian_consent', 'Parent/Guardian Consent (notarized)',
     'Notarized parent or guardian consent for the planned activity.', 'pre_activity', true, false),
    ('medical_clearance', 'Medical Clearance',
     'Medical clearance for participation; treat supporting information as sensitive.', 'pre_activity', false, true),
    ('student_learning_journal', 'Student Learning Journal',
     'Student reflection and learning outcomes following the activity.', 'post_activity', false, false)
ON CONFLICT (code) DO NOTHING;

-- Match the existing custom-JWT backend model: clients cannot query these
-- tables directly. FastAPI authorizes end users; smartevent_app is server-only.
DO $$
DECLARE table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['document_routing', 'requirement_presets',
        'event_participants', 'event_requirements', 'student_compliance_records']
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO smartevent_app', table_name);
        EXECUTE format('CREATE POLICY smartevent_backend_only ON public.%I FOR ALL TO smartevent_app
            USING (true) WITH CHECK (true)', table_name);
    END LOOP;
END $$;
REVOKE INSERT, UPDATE, DELETE ON public.requirement_presets FROM smartevent_app;

COMMIT;
