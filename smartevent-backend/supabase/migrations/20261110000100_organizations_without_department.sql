BEGIN;

-- Some organizations belong to no department. Their members and records carry a
-- blank department, and their proposals go from the Moderator straight to the
-- SDS Office, since there is no Dean.
ALTER TABLE public.organizations ALTER COLUMN department_id DROP NOT NULL;
ALTER TABLE public.receipts ALTER COLUMN department_id DROP NOT NULL;

-- Members need an organization; an Admin, who is a Dean, also needs a department.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_scope_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_scope_check CHECK (
    (role IN ('super_admin', 'sds_staff', 'signatory') AND department_id IS NULL AND organization_id IS NULL)
    OR (role = 'admin' AND department_id IS NOT NULL AND organization_id IS NOT NULL)
    OR (role IN ('adviser', 'treasurer', 'officer') AND organization_id IS NOT NULL)
) NOT VALID;

-- Failsafe: an account or roster row always carries its organization's department.
-- The (organization_id, department_id) foreign keys are MATCH SIMPLE, so on their
-- own they would let a blank department through beside an organization that has one.
CREATE FUNCTION public.enforce_organization_department() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NEW.organization_id IS NOT NULL AND NEW.department_id IS DISTINCT FROM
        (SELECT o.department_id FROM public.organizations o WHERE o.id = NEW.organization_id) THEN
        RAISE EXCEPTION 'Department must be the organization''s own department';
    END IF;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.enforce_organization_department() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enforce_organization_department() TO smartevent_app;
CREATE TRIGGER users_organization_department BEFORE INSERT OR UPDATE OF organization_id, department_id
    ON public.users FOR EACH ROW EXECUTE FUNCTION public.enforce_organization_department();
CREATE TRIGGER cite_members_organization_department BEFORE INSERT OR UPDATE OF organization_id, department_id
    ON public.cite_members FOR EACH ROW EXECUTE FUNCTION public.enforce_organization_department();

-- These compared departments with '=', which is never true for two blanks.
CREATE OR REPLACE FUNCTION public.enforce_receipt_transaction_link() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE linked_event UUID; linked_amount NUMERIC; event_org UUID; event_department UUID;
BEGIN
    IF NEW.expense_id IS NOT NULL THEN
        SELECT event_id, amount INTO linked_event, linked_amount FROM expenses WHERE id = NEW.expense_id;
        IF NOT EXISTS (SELECT 1 FROM expenses WHERE id = NEW.expense_id
                       AND organization_id = NEW.organization_id
                       AND department_id IS NOT DISTINCT FROM NEW.department_id) THEN
            RAISE EXCEPTION 'Receipt expense scope mismatch';
        END IF;
    ELSE
        SELECT event_id, amount INTO linked_event, linked_amount FROM income_records WHERE id = NEW.income_id;
    END IF;
    SELECT organization_id, department_id INTO event_org, event_department FROM events WHERE id = NEW.event_id;
    IF linked_event IS DISTINCT FROM NEW.event_id OR linked_amount IS DISTINCT FROM NEW.amount
        OR event_org IS DISTINCT FROM NEW.organization_id OR event_department IS DISTINCT FROM NEW.department_id THEN
        RAISE EXCEPTION 'Receipt must match its transaction event, amount, and ownership';
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.enforce_inventory_event_scope() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NEW.event_id IS NULL OR NOT EXISTS (SELECT 1 FROM events e WHERE e.id = NEW.event_id
        AND e.organization_id = NEW.organization_id AND e.department_id IS NOT DISTINCT FROM NEW.department_id) THEN
        RAISE EXCEPTION 'Inventory requires an event in the same organization and department';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.event_id IS NOT NULL AND NEW.event_id IS DISTINCT FROM OLD.event_id THEN
            RAISE EXCEPTION 'Initial inventory event is immutable';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.enforce_inventory_movement_scope() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM inventory i JOIN events e ON e.id = NEW.event_id
        WHERE i.id = NEW.inventory_id AND i.organization_id = e.organization_id
        AND i.department_id IS NOT DISTINCT FROM e.department_id AND i.event_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Inventory movement event scope mismatch';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF NEW.change_qty IS DISTINCT FROM OLD.change_qty OR NEW.inventory_id IS DISTINCT FROM OLD.inventory_id
            OR NEW.expense_item_id IS DISTINCT FROM OLD.expense_item_id
            OR (OLD.event_id IS NOT NULL AND NEW.event_id IS DISTINCT FROM OLD.event_id)
            OR (OLD.transaction_type <> 'legacy' AND NEW.transaction_type IS DISTINCT FROM OLD.transaction_type) THEN
            RAISE EXCEPTION 'Movement quantity and recorded provenance are immutable';
        END IF;
    END IF;
    IF NEW.transaction_type = 'purchase' THEN
        IF NOT EXISTS (SELECT 1 FROM expense_items line
            JOIN expenses ex ON ex.id = line.expense_id
            JOIN inventory i ON i.id = NEW.inventory_id
            JOIN receipts r ON r.expense_id = ex.id
            WHERE line.id = NEW.expense_item_id AND line.category = 'asset'
                AND line.converted_inventory_id = NEW.inventory_id AND line.quantity = NEW.change_qty
                AND lower(trim(line.unit)) = lower(trim(i.unit))
                AND ex.status = 'approved' AND ex.purchase_completed_at IS NOT NULL
                AND ex.event_id = NEW.event_id AND ex.organization_id = i.organization_id
                AND ex.department_id IS NOT DISTINCT FROM i.department_id AND ex.paid_amount = ex.amount
                AND ex.paid_on <= CURRENT_DATE AND ex.received_on <= CURRENT_DATE
                AND r.event_id = ex.event_id AND r.amount = ex.amount
                AND r.review_status IN ('clear','cleared') AND length(trim(r.purpose)) > 0) THEN
            RAISE EXCEPTION 'Purchased stock requires a completed, paid and received, receipted asset transaction';
        END IF;
    END IF;
    RETURN NEW;
END $$;

COMMIT;
