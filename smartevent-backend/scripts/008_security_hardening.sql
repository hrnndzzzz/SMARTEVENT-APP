-- Apply after 001-007 as the schema owner; deploy the API only after this script.
-- Adjust bucket IDs below if SUPABASE_*_BUCKET uses custom names.
BEGIN;

-- Stock balances depend on the existing, enabled database movement trigger.
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE t.tgrelid = 'public.inventory_transactions'::regclass
            AND NOT t.tgisinternal AND t.tgenabled IN ('O', 'A')
            AND (t.tgtype & 1) = 1 AND (t.tgtype & 4) = 4 AND (t.tgtype & 2) = 0
            AND n.nspname = 'public' AND p.proname = 'fn_apply_inventory_transaction'
    ) THEN
        RAISE EXCEPTION 'An enabled AFTER INSERT inventory stock trigger is required before API deployment';
    END IF;
END $$;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS login_failed_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS login_locked_until TIMESTAMPTZ;
ALTER TABLE public.otp_tokens ADD COLUMN IF NOT EXISTS failed_attempts INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS users_email_case_insensitive_key ON public.users (lower(email));
CREATE UNIQUE INDEX IF NOT EXISTS cite_members_email_case_insensitive_key ON public.cite_members (lower(email));

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_login_attempts_valid'
                   AND conrelid = 'public.users'::regclass) THEN
        ALTER TABLE public.users ADD CONSTRAINT users_login_attempts_valid CHECK (login_failed_attempts >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'otp_failed_attempts_valid'
                   AND conrelid = 'public.otp_tokens'::regclass) THEN
        ALTER TABLE public.otp_tokens ADD CONSTRAINT otp_failed_attempts_valid CHECK (failed_attempts BETWEEN 0 AND 5);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartevent_app') THEN
        CREATE ROLE smartevent_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
    END IF;
END $$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated, service_role, smartevent_app;
GRANT USAGE ON SCHEMA public TO smartevent_app;

-- Custom app JWTs are authorized by FastAPI, never by Supabase's Data API.
DO $$
DECLARE table_name TEXT; function_record RECORD;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'departments', 'organizations', 'users', 'otp_tokens', 'cite_members',
        'notifications', 'categories', 'events', 'approvals', 'expenses',
        'income_records', 'receipts', 'inventory', 'expense_items',
        'inventory_transactions', 'audit_logs', 'event_proposal_letters'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO smartevent_app', table_name);
        IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'smartevent_backend_only'
                       AND polrelid = format('public.%I', table_name)::regclass) THEN
            EXECUTE format('CREATE POLICY smartevent_backend_only ON public.%I FOR ALL TO smartevent_app
                            USING (true) WITH CHECK (true)', table_name);
        END IF;
    END LOOP;
    FOR function_record IN SELECT p.oid::regprocedure AS signature FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN (
            'enforce_receipt_transaction_link', 'protect_receipted_transaction',
            'enforce_inventory_event_scope', 'enforce_inventory_movement_scope',
            'fn_deduct_category_balance', 'fn_apply_inventory_transaction', 'fn_deduct_event_budget')
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', function_record.signature);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO smartevent_app', function_record.signature);
        EXECUTE format('ALTER FUNCTION %s SET search_path = pg_catalog, public, pg_temp', function_record.signature);
    END LOOP;
END $$;

REVOKE UPDATE, DELETE ON public.audit_logs FROM smartevent_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

UPDATE storage.buckets SET public = false, file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg'] WHERE id = 'receipts';
UPDATE storage.buckets SET public = false, file_size_limit = 10485760,
    allowed_mime_types = ARRAY['application/pdf', 'image/jpeg'] WHERE id = 'proposal-letters';

-- Restrictive rules override old permissive storage policies for these buckets.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'smartevent_private_documents'
                   AND polrelid = 'storage.objects'::regclass) THEN
        CREATE POLICY smartevent_private_documents ON storage.objects AS RESTRICTIVE
            FOR ALL TO anon, authenticated
            USING (bucket_id NOT IN ('receipts', 'proposal-letters'))
            WITH CHECK (bucket_id NOT IN ('receipts', 'proposal-letters'));
    END IF;
END $$;

COMMIT;

-- Grant smartevent_app to a dedicated server login; keep that login out of clients.
-- Table owners remain migration-only. Disable the unused Supabase Data API.
