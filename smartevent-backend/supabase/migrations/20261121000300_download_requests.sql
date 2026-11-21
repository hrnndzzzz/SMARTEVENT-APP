BEGIN;

-- Requests for the Android build, from the public website. Whoever asks has no
-- account and may never get one, so this is not a user row: it is a question
-- put to the department, kept so it cannot be lost in a mailbox.
CREATE TABLE IF NOT EXISTS public.download_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar(150) NOT NULL,
    email varchar(255) NOT NULL,
    organization varchar(150) NOT NULL,
    -- What the visitor says they are, which nobody has checked. Not the users
    -- role enum: a request naming something else is still worth reading.
    role varchar(50) NOT NULL,
    reason text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'pending',
    decided_by uuid REFERENCES public.users(id),
    decided_at timestamptz,
    note text,
    email_status varchar(20) NOT NULL DEFAULT 'not_sent',
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.download_requests DROP CONSTRAINT IF EXISTS download_request_status_valid;
ALTER TABLE public.download_requests ADD CONSTRAINT download_request_status_valid CHECK (
    status IN ('pending','approved','rejected')
);

ALTER TABLE public.download_requests DROP CONSTRAINT IF EXISTS download_request_email_status_valid;
ALTER TABLE public.download_requests ADD CONSTRAINT download_request_email_status_valid CHECK (
    email_status IN ('not_sent','sent','failed')
);

-- Decided means decided by somebody, at a time, and only then. Without this a
-- bug could leave a row approved with nobody's name against it.
ALTER TABLE public.download_requests DROP CONSTRAINT IF EXISTS download_request_decision_complete;
ALTER TABLE public.download_requests ADD CONSTRAINT download_request_decision_complete CHECK (
    (status = 'pending' AND decided_by IS NULL AND decided_at IS NULL)
    OR (status <> 'pending' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)
);

ALTER TABLE public.download_requests DROP CONSTRAINT IF EXISTS download_request_text_present;
ALTER TABLE public.download_requests ADD CONSTRAINT download_request_text_present CHECK (
    length(trim(name)) > 1 AND length(trim(email)) > 2 AND length(trim(organization)) > 1
    AND length(trim(role)) > 1 AND length(trim(reason)) > 9
);

-- One pending request per address, case-insensitively. This index is what the
-- website's 409 is made of: the endpoint inserts and reports the conflict,
-- rather than reading first — two submissions arriving together would both
-- find nothing and both insert.
CREATE UNIQUE INDEX IF NOT EXISTS uq_download_request_pending
    ON public.download_requests (lower(email)) WHERE status = 'pending';

-- Decided requests are read by address when somebody asks again later.
CREATE INDEX IF NOT EXISTS ix_download_requests_email
    ON public.download_requests (email);

-- Reached only through the API, like the refresh tokens: nobody holding an
-- anon or authenticated key gets to read what members of the public wrote
-- about themselves, even though the route that writes it needs no session.
ALTER TABLE public.download_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.download_requests FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.download_requests TO smartevent_app;
DROP POLICY IF EXISTS smartevent_backend_only ON public.download_requests;
CREATE POLICY smartevent_backend_only ON public.download_requests FOR ALL TO smartevent_app USING (true) WITH CHECK (true);

COMMIT;
