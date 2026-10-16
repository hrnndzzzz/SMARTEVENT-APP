-- Phase 3: printable attendance and staff-managed post-activity work.
-- Apply once AFTER Phase 2. Existing approvals/completion statuses are preserved.
BEGIN;
DO $$ BEGIN
    IF to_regclass('public.event_compliance_documents') IS NULL THEN
        RAISE EXCEPTION 'Apply Phase 2 before Phase 3';
    END IF;
END $$;
ALTER TABLE public.events
    ADD COLUMN completed_on DATE,
    ADD COLUMN completed_at TIMESTAMPTZ,
    ADD COLUMN completed_by UUID REFERENCES public.users(id);
CREATE INDEX ix_events_completed_by ON public.events (completed_by);
ALTER TABLE public.event_participants
    ADD COLUMN participation_mode VARCHAR(20) NOT NULL DEFAULT 'attending',
    ADD CONSTRAINT participant_mode_check CHECK (participation_mode IN ('attending', 'parallel'));
ALTER TABLE public.event_compliance_documents DROP CONSTRAINT event_document_kind_check;
ALTER TABLE public.event_compliance_documents ADD CONSTRAINT event_document_kind_check CHECK (
    (vehicle_id IS NULL AND kind IN ('lgu_coordination', 'agency_acknowledgment', 'signed_attendance', 'debriefing_report', 'final_expense_report')) OR
    (vehicle_id IS NOT NULL AND kind IN ('vehicle_registration', 'insurance', 'driver_license', 'roadworthiness', 'ltfrb_franchise', 'dot_accreditation', 'ltfrb_special_permit'))
);
CREATE TABLE public.event_parallel_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    participant_id UUID NOT NULL,
    title VARCHAR(200) NOT NULL,
    learning_objectives TEXT NOT NULL,
    instructions TEXT NOT NULL,
    reason TEXT NOT NULL,
    due_date DATE,
    assigned_by UUID NOT NULL REFERENCES public.users(id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    status VARCHAR(20) NOT NULL DEFAULT 'ASSIGNED',
    version INTEGER NOT NULL DEFAULT 1,
    document_url TEXT,
    submitted_by UUID REFERENCES public.users(id),
    submitted_at TIMESTAMPTZ,
    evidence_mode VARCHAR(20),
    reviewed_by UUID REFERENCES public.users(id),
    reviewed_at TIMESTAMPTZ,
    remarks TEXT,
    CONSTRAINT uq_parallel_participant UNIQUE (participant_id),
    CONSTRAINT parallel_participant_event_fk FOREIGN KEY (participant_id, event_id)
        REFERENCES public.event_participants (id, event_id),
    CONSTRAINT parallel_status_check CHECK (status IN ('ASSIGNED', 'SUBMITTED', 'VERIFIED', 'REJECTED')),
    CONSTRAINT parallel_version_check CHECK (version > 0),
    CONSTRAINT parallel_evidence_check CHECK (evidence_mode IS NULL OR evidence_mode IN ('digital', 'physical')),
    CONSTRAINT parallel_review_check CHECK (status NOT IN ('VERIFIED', 'REJECTED') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);
CREATE INDEX ix_event_parallel_activities_event_id ON public.event_parallel_activities (event_id);
CREATE INDEX ix_parallel_participant_event ON public.event_parallel_activities (participant_id, event_id);
CREATE INDEX ix_event_parallel_activities_assigned_by ON public.event_parallel_activities (assigned_by);
CREATE INDEX ix_event_parallel_activities_submitted_by ON public.event_parallel_activities (submitted_by);
CREATE INDEX ix_event_parallel_activities_reviewed_by ON public.event_parallel_activities (reviewed_by);
ALTER TABLE public.event_parallel_activities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_parallel_activities FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.event_parallel_activities TO smartevent_app;
CREATE POLICY smartevent_backend_only ON public.event_parallel_activities FOR ALL TO smartevent_app USING (true) WITH CHECK (true);
COMMIT;
