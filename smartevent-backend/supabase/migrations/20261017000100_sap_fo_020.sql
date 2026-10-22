-- SAP 001: additive, separate from generic routing. Apply after phases 1–3.
BEGIN;
ALTER TABLE public.events ADD COLUMN start_time time, ADD COLUMN end_time time;
ALTER TABLE public.events ADD CONSTRAINT event_local_time_window
    CHECK ((start_time IS NULL AND end_time IS NULL) OR
           (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time));
-- Registration remains one-time; workflow notifications recur per transition.
ALTER TABLE public.notifications DROP CONSTRAINT uq_notification_user_kind;
CREATE UNIQUE INDEX uq_registration_notification ON public.notifications(user_id, kind)
    WHERE kind = 'registration_confirmation';
CREATE TABLE public.sap_proposals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL UNIQUE REFERENCES public.events(id),
    form_code varchar(30) NOT NULL DEFAULT 'SAS-SDS-FO-020',
    form_version varchar(10) NOT NULL DEFAULT '001',
    state varchar(30) NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','pending_sap_review','revision_requested','approved','completed','rejected')),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    revision_no integer NOT NULL DEFAULT 0 CHECK (revision_no >= 0),
    details json NOT NULL DEFAULT '{}', clearance json, return_remarks text
);
CREATE TABLE public.sap_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL REFERENCES public.sap_proposals(id),
    kind varchar(30) NOT NULL CHECK (kind IN ('program-flow','budget-items','support-requests','affected-classes')),
    ordinal integer NOT NULL CHECK (ordinal >= 0), data json NOT NULL,
    UNIQUE (proposal_id, kind, ordinal)
);
CREATE INDEX ix_sap_items_proposal_id ON public.sap_items(proposal_id);
CREATE TABLE public.sap_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL REFERENCES public.sap_proposals(id),
    revision_no integer NOT NULL CHECK (revision_no > 0), snapshot json NOT NULL,
    printable_pdf bytea NOT NULL, pdf_sha256 varchar(64) NOT NULL,
    verification_token varchar(64) NOT NULL UNIQUE,
    submitted_by uuid NOT NULL REFERENCES public.users(id),
    submitted_at timestamptz NOT NULL DEFAULT now(), UNIQUE (proposal_id, revision_no)
);
CREATE INDEX ix_sap_revisions_proposal_id ON public.sap_revisions(proposal_id);
CREATE TABLE public.sap_checkpoints (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    revision_id uuid NOT NULL REFERENCES public.sap_revisions(id),
    slot integer NOT NULL CHECK (slot BETWEEN 1 AND 9),
    position varchar(200) NOT NULL, label varchar(50) NOT NULL, evidence json,
    recorded_by uuid REFERENCES public.users(id), recorded_at timestamptz,
    UNIQUE(revision_id, slot),
    CHECK ((evidence IS NULL AND recorded_by IS NULL AND recorded_at IS NULL) OR
           (evidence IS NOT NULL AND recorded_by IS NOT NULL AND recorded_at IS NOT NULL))
);
CREATE INDEX ix_sap_checkpoints_revision_id ON public.sap_checkpoints(revision_id);
CREATE TABLE public.sap_final_copies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    revision_id uuid NOT NULL UNIQUE REFERENCES public.sap_revisions(id),
    storage_ref text NOT NULL, sha256 varchar(64) NOT NULL,
    uploaded_by uuid NOT NULL REFERENCES public.users(id), uploaded_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.sap_evaluations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL UNIQUE REFERENCES public.sap_proposals(id),
    outcome varchar(20) NOT NULL CHECK (outcome IN ('conducted','canceled')),
    remarks text NOT NULL CHECK (length(trim(remarks)) > 0),
    evaluated_by uuid NOT NULL REFERENCES public.users(id), evaluated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.event_logistics DROP CONSTRAINT logistics_location_check;
ALTER TABLE public.event_logistics ADD CONSTRAINT logistics_location_check
    CHECK (activity_location IN ('on_campus','off_campus','online'));

-- Clients have no direct database access; FastAPI authenticates and authorizes users.
DO $$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['sap_proposals','sap_items','sap_revisions','sap_checkpoints','sap_final_copies','sap_evaluations'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO smartevent_app', table_name);
        EXECUTE format('CREATE POLICY smartevent_backend_only ON public.%I FOR ALL TO smartevent_app USING (true) WITH CHECK (true)', table_name);
    END LOOP;
END $$;
REVOKE UPDATE, DELETE ON public.sap_revisions, public.sap_final_copies, public.sap_evaluations FROM smartevent_app;
REVOKE DELETE ON public.sap_checkpoints, public.sap_proposals FROM smartevent_app;

CREATE FUNCTION public.sap_immutable_evidence() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    RAISE EXCEPTION 'SAP evidence is immutable; submit a new revision';
END $$;
CREATE TRIGGER sap_revision_immutable BEFORE UPDATE OR DELETE ON public.sap_revisions
    FOR EACH ROW EXECUTE FUNCTION public.sap_immutable_evidence();
CREATE TRIGGER sap_final_copy_immutable BEFORE UPDATE OR DELETE ON public.sap_final_copies
    FOR EACH ROW EXECUTE FUNCTION public.sap_immutable_evidence();
CREATE TRIGGER sap_evaluation_immutable BEFORE UPDATE OR DELETE ON public.sap_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.sap_immutable_evidence();

CREATE FUNCTION public.sap_checkpoint_write_once() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'SAP checkpoints cannot be deleted';
    END IF;
    IF OLD.evidence IS NOT NULL OR NEW.id <> OLD.id OR NEW.revision_id <> OLD.revision_id
        OR NEW.slot <> OLD.slot OR NEW.position <> OLD.position OR NEW.label <> OLD.label THEN
        RAISE EXCEPTION 'SAP checkpoint identity and recorded evidence are immutable';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sap_checkpoint_immutable BEFORE UPDATE OR DELETE ON public.sap_checkpoints
    FOR EACH ROW EXECUTE FUNCTION public.sap_checkpoint_write_once();

-- Reuse the existing private proposal-letters bucket. No new storage.objects
-- client policy is introduced; upload service also checks bucket.public=false.
COMMIT;
