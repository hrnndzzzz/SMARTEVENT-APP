BEGIN;

-- A device's renewal key, kept only as a SHA-256 hash. It is swapped for a fresh
-- access token without the password, so a phone that was offline for hours is
-- not asked to sign in again. Signing out, a password change or reset, and a
-- suspended account end it.
CREATE TABLE public.refresh_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_hash varchar(64) NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX ix_refresh_tokens_user_id ON public.refresh_tokens(user_id);
ALTER TABLE public.refresh_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.refresh_tokens FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.refresh_tokens TO smartevent_app;
CREATE POLICY smartevent_backend_only ON public.refresh_tokens FOR ALL TO smartevent_app USING (true) WITH CHECK (true);

-- A draft event that was never sent for review can now be deleted with its
-- proposal and files. One sent even once keeps its paper trail: the trigger
-- refuses it here as well as in the API.
GRANT DELETE ON public.sap_proposals, public.sap_attachments TO smartevent_app;
CREATE FUNCTION public.sap_delete_only_unsent() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF TG_TABLE_NAME = 'sap_proposals' THEN
        IF OLD.revision_no <> 0 THEN
            RAISE EXCEPTION 'A proposal sent for review is kept';
        END IF;
    ELSIF EXISTS (SELECT 1 FROM public.sap_proposals p WHERE p.id = OLD.proposal_id AND p.revision_no <> 0) THEN
        RAISE EXCEPTION 'The files of a proposal sent for review are kept';
    END IF;
    RETURN OLD;
END $$;
CREATE TRIGGER sap_proposal_delete_only_unsent BEFORE DELETE ON public.sap_proposals
    FOR EACH ROW EXECUTE FUNCTION public.sap_delete_only_unsent();
CREATE TRIGGER sap_attachment_delete_only_unsent BEFORE DELETE ON public.sap_attachments
    FOR EACH ROW EXECUTE FUNCTION public.sap_delete_only_unsent();

COMMIT;
