BEGIN;

-- The treasurer and signatory roles are gone.
--
-- A treasurer is an officer who holds that position, which lives in
-- users.position and needs no role of its own, so every treasurer account
-- becomes an officer and keeps its title. The institutional signatories
-- sign the printed Student Activity Proposal instead of reviewing in the
-- app, so document_routing has nothing left to hold.
--
-- The SDS Office still reviews proposals, and an event still passes through
-- 'pending_institutional_review' on its way there — services/sap.py puts it
-- there when the Dean approves. Only the signatories' half of that status
-- is being removed.

-- Officers by role, treasurers by title. Position is free text, so an
-- account with no position at all is given one rather than losing the fact.
UPDATE public.users
SET role = 'officer',
    position = COALESCE(NULLIF(TRIM(position), ''), 'Treasurer')
WHERE role = 'treasurer';

UPDATE public.cite_members
SET role = 'officer',
    position = COALESCE(NULLIF(TRIM(position), ''), 'Treasurer')
WHERE role = 'treasurer';

-- Signatory accounts are deactivated rather than deleted: they own audit
-- rows and past routing decisions, and a deleted user takes its history
-- with it. They are school-wide accounts with no operational scope, so a
-- suspended one can do nothing.
UPDATE public.users
SET is_active = FALSE,
    is_suspended = TRUE
WHERE role = 'signatory';

DELETE FROM public.cite_members WHERE role = 'signatory';

-- Any event still waiting on signatures is handed to the Dean's decision.
-- Without this they sit in a status no one can act on: the step that moved
-- them out of it no longer exists.
UPDATE public.events
SET status = 'approved'
WHERE status = 'pending_institutional_review'
  AND id NOT IN (SELECT event_id FROM public.sap_proposals);

DROP TABLE IF EXISTS public.document_routing;

-- Signatory rows are kept, deactivated, so the role has to stay legal here.
-- The check is about what may be created from now on, and no endpoint can
-- set it any more.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_check CHECK (
    role IN ('super_admin', 'admin', 'adviser', 'officer', 'sds_staff', 'signatory')
) NOT VALID;

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_scope_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_scope_check CHECK (
    (role IN ('super_admin', 'sds_staff', 'signatory') AND department_id IS NULL AND organization_id IS NULL)
    OR (role = 'admin' AND department_id IS NOT NULL AND organization_id IS NOT NULL)
    OR (role IN ('adviser', 'officer') AND organization_id IS NOT NULL)
) NOT VALID;

COMMIT;
