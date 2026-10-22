-- Read-only staging verification after the SAP migration, run as deployment owner.
-- This does not apply migrations or alter roles, policies, records or files.
-- Run against a disposable/staging PostgreSQL instance, not via a client JWT.
BEGIN;
DO $$
DECLARE
    table_name text;
    client_role text;
    qualified_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['sap_proposals','sap_items','sap_revisions','sap_checkpoints','sap_final_copies','sap_evaluations'] LOOP
        qualified_name := 'public.' || table_name;
        IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid
                       WHERE n.nspname='public' AND c.relname=table_name AND c.relrowsecurity) THEN
            RAISE EXCEPTION 'RLS is not enabled on %', qualified_name;
        END IF;
        FOREACH client_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            IF has_table_privilege(client_role, qualified_name, 'SELECT,INSERT,UPDATE,DELETE') THEN
                RAISE EXCEPTION 'Client role % has access to %', client_role, qualified_name;
            END IF;
        END LOOP;
        IF NOT has_table_privilege('smartevent_app', qualified_name, 'SELECT')
           OR NOT has_table_privilege('smartevent_app', qualified_name, 'INSERT') THEN
            RAISE EXCEPTION 'Backend cannot read/insert %', qualified_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                       AND tablename=table_name AND policyname='smartevent_backend_only'
                       AND 'smartevent_app'=ANY(roles)) THEN
            RAISE EXCEPTION 'Backend-only policy missing for %', qualified_name;
        END IF;
    END LOOP;
    FOREACH table_name IN ARRAY ARRAY['sap_revisions','sap_final_copies','sap_evaluations'] LOOP
        IF has_table_privilege('smartevent_app', 'public.' || table_name, 'UPDATE,DELETE') THEN
            RAISE EXCEPTION 'Backend can mutate immutable %', table_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=('public.' || table_name)::regclass
                       AND NOT tgisinternal AND tgenabled='O') THEN
            RAISE EXCEPTION 'Immutable trigger missing on %', table_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='proposal-letters' AND public=false) THEN
        RAISE EXCEPTION 'Default proposal-letters bucket must exist and be private (adapt this check if configured differently)';
    END IF;
END $$;
ROLLBACK;
