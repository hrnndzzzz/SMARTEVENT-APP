BEGIN;

-- A deleted draft is kept whole for 30 days, its files with it, so it can be
-- recovered by hand; the backend's daily cleanup then removes both for good.
CREATE TABLE public.deleted_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL,
    organization_id uuid,
    title varchar(200) NOT NULL,
    deleted_by uuid NOT NULL REFERENCES public.users(id),
    deleted_at timestamptz NOT NULL DEFAULT now(),
    snapshot json NOT NULL,
    storage_refs json NOT NULL DEFAULT '[]'
);
CREATE INDEX ix_deleted_events_deleted_at ON public.deleted_events(deleted_at);
ALTER TABLE public.deleted_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.deleted_events FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, DELETE ON TABLE public.deleted_events TO smartevent_app;
CREATE POLICY smartevent_backend_only ON public.deleted_events FOR ALL TO smartevent_app USING (true) WITH CHECK (true);

-- The program flow may be attached as a file instead of typed in as rows.
ALTER TABLE public.sap_attachments DROP CONSTRAINT sap_attachments_category_check;
ALTER TABLE public.sap_attachments ADD CONSTRAINT sap_attachments_category_check
    CHECK (category IN ('apf','pcf','appendix','roc_coc','program_flow','other'));

COMMIT;
