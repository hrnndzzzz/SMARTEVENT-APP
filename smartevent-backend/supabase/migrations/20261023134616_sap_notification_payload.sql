-- Additive: existing notifications remain readable with a null payload.
-- Deploy before the Release 2 backend; existing grants and RLS are unchanged.
BEGIN;
ALTER TABLE public.notifications ADD COLUMN payload jsonb;
COMMIT;
