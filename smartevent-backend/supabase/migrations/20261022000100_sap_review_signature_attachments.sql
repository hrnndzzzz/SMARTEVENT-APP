BEGIN;
ALTER TABLE public.sap_proposals DROP CONSTRAINT sap_proposals_state_check;
ALTER TABLE public.sap_proposals ADD CONSTRAINT sap_proposals_state_check
    CHECK (state IN ('draft','pending_sap_review','revision_requested','sds_signed','approved','completed','rejected'));
CREATE TABLE public.sap_attachments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL REFERENCES public.sap_proposals(id),
    revision_no integer NOT NULL CHECK (revision_no > 0),
    category varchar(30) NOT NULL CHECK (category IN ('apf','pcf','appendix','roc_coc','other')),
    display_name varchar(150) NOT NULL, file_name varchar(255) NOT NULL,
    content_type varchar(80) NOT NULL, storage_ref text NOT NULL, sha256 varchar(64) NOT NULL,
    uploaded_by uuid NOT NULL REFERENCES public.users(id), uploaded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_sap_attachments_proposal_revision ON public.sap_attachments(proposal_id, revision_no);
CREATE TABLE public.sap_reviews (
    revision_id uuid PRIMARY KEY REFERENCES public.sap_revisions(id),
    overall_remarks text NOT NULL DEFAULT '', section_remarks json NOT NULL DEFAULT '{}',
    signature_strokes json, signed_by uuid REFERENCES public.users(id), signed_at timestamptz,
    signed_pdf bytea, signed_pdf_sha256 varchar(64),
    CHECK ((signed_at IS NULL AND signed_by IS NULL AND signature_strokes IS NULL AND signed_pdf IS NULL AND signed_pdf_sha256 IS NULL) OR
           (signed_at IS NOT NULL AND signed_by IS NOT NULL AND signature_strokes IS NOT NULL AND signed_pdf IS NOT NULL AND signed_pdf_sha256 IS NOT NULL))
);
DO $$ DECLARE table_name text; BEGIN
    FOREACH table_name IN ARRAY ARRAY['sap_attachments','sap_reviews'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO smartevent_app', table_name);
        EXECUTE format('CREATE POLICY smartevent_backend_only ON public.%I FOR ALL TO smartevent_app USING (true) WITH CHECK (true)', table_name);
    END LOOP;
END $$;
REVOKE DELETE ON public.sap_reviews FROM smartevent_app;
REVOKE DELETE ON public.sap_attachments FROM smartevent_app;
CREATE FUNCTION public.sap_review_write_once() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF TG_OP = 'DELETE' OR OLD.signed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Signed SAP review is immutable; submit a new revision';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sap_review_immutable BEFORE UPDATE OR DELETE ON public.sap_reviews
    FOR EACH ROW EXECUTE FUNCTION public.sap_review_write_once();
COMMIT;
