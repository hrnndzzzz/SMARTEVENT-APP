-- Phase 2: apply once, after 008 and Phase 1, as schema owner.
-- No account provisioning, public storage, or changes to historical approvals.
BEGIN;
DO $$ BEGIN
    IF to_regclass('public.student_compliance_records') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartevent_app') THEN
        RAISE EXCEPTION 'Apply security hardening 008 and Phase 1 before Phase 2';
    END IF;
END $$;

ALTER TABLE public.event_participants ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.student_compliance_records
    ADD COLUMN document_url TEXT,
    ADD COLUMN submitted_by UUID REFERENCES public.users(id),
    ADD COLUMN submitted_at TIMESTAMPTZ,
    ADD COLUMN evidence_mode VARCHAR(20),
    ADD COLUMN notarization_confirmed BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN version INTEGER NOT NULL DEFAULT 1,
    ADD CONSTRAINT compliance_version_check CHECK (version > 0),
    ADD CONSTRAINT compliance_evidence_mode_check CHECK (evidence_mode IS NULL OR evidence_mode IN ('digital', 'physical'));
CREATE INDEX ix_student_compliance_records_submitted_by ON public.student_compliance_records (submitted_by);
CREATE INDEX ix_compliance_participant_event ON public.student_compliance_records (participant_id, event_id);
CREATE INDEX ix_compliance_requirement_event ON public.student_compliance_records (requirement_id, event_id);

CREATE TABLE public.event_logistics (
    event_id UUID PRIMARY KEY REFERENCES public.events(id),
    activity_location VARCHAR(20) NOT NULL,
    destination VARCHAR(300) NOT NULL,
    transport_mode VARCHAR(20) NOT NULL DEFAULT 'none',
    transport_notes TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT logistics_location_check CHECK (activity_location IN ('on_campus', 'off_campus')),
    CONSTRAINT logistics_transport_check CHECK (transport_mode IN ('none', 'institution', 'third_party'))
);
CREATE TABLE public.event_personnel (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    staff_reference VARCHAR(50) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    position VARCHAR(100) NOT NULL,
    qualifications VARCHAR(1000) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT uq_event_personnel_reference UNIQUE (event_id, staff_reference)
);
CREATE INDEX ix_event_personnel_event_id ON public.event_personnel (event_id);
CREATE TABLE public.event_vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    plate_number VARCHAR(30) NOT NULL,
    operator_name VARCHAR(150) NOT NULL,
    driver_name VARCHAR(150) NOT NULL,
    out_of_line BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT uq_event_vehicle_plate UNIQUE (event_id, plate_number),
    CONSTRAINT uq_vehicle_id_event UNIQUE (id, event_id)
);
CREATE INDEX ix_event_vehicles_event_id ON public.event_vehicles (event_id);
CREATE TABLE public.event_compliance_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id),
    vehicle_id UUID,
    document_key VARCHAR(100) NOT NULL,
    kind VARCHAR(40) NOT NULL,
    document_url TEXT NOT NULL,
    reference_number VARCHAR(150) NOT NULL,
    valid_until DATE,
    validity_confirmed BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'SUBMITTED',
    version INTEGER NOT NULL DEFAULT 1,
    submitted_by UUID NOT NULL REFERENCES public.users(id),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by UUID REFERENCES public.users(id),
    reviewed_at TIMESTAMPTZ,
    remarks TEXT,
    CONSTRAINT uq_event_document_key UNIQUE (event_id, document_key),
    CONSTRAINT compliance_document_vehicle_fk FOREIGN KEY (vehicle_id, event_id)
        REFERENCES public.event_vehicles (id, event_id),
    CONSTRAINT event_document_status_check CHECK (status IN ('SUBMITTED', 'VERIFIED', 'REJECTED')),
    CONSTRAINT event_document_version_check CHECK (version > 0),
    CONSTRAINT event_document_review_check CHECK (status = 'SUBMITTED' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
    CONSTRAINT event_document_kind_check CHECK (
        (vehicle_id IS NULL AND kind IN ('lgu_coordination', 'agency_acknowledgment')) OR
        (vehicle_id IS NOT NULL AND kind IN ('vehicle_registration', 'insurance', 'driver_license', 'roadworthiness', 'ltfrb_franchise', 'dot_accreditation', 'ltfrb_special_permit'))
    )
);
CREATE INDEX ix_event_compliance_documents_event_id ON public.event_compliance_documents (event_id);
CREATE INDEX ix_event_compliance_documents_vehicle_id ON public.event_compliance_documents (vehicle_id);
CREATE INDEX ix_event_compliance_documents_submitted_by ON public.event_compliance_documents (submitted_by);
CREATE INDEX ix_event_compliance_documents_reviewed_by ON public.event_compliance_documents (reviewed_by);
CREATE INDEX ix_compliance_document_vehicle_event ON public.event_compliance_documents (vehicle_id, event_id);

-- Custom-JWT authorization is enforced by FastAPI. No direct client table access.
DO $$ DECLARE table_name TEXT; BEGIN
    FOREACH table_name IN ARRAY ARRAY['event_logistics', 'event_personnel', 'event_vehicles', 'event_compliance_documents'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO smartevent_app', table_name);
        EXECUTE format('CREATE POLICY smartevent_backend_only ON public.%I FOR ALL TO smartevent_app USING (true) WITH CHECK (true)', table_name);
    END LOOP;
END $$;
COMMIT;
