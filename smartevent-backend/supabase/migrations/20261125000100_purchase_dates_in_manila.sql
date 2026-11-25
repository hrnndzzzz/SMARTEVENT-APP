BEGIN;

-- A purchase paid and received "today" was refused between midnight and 8 a.m.
-- in Manila. The API holds those dates to Manila's today (institution_today),
-- but this rule compared them with CURRENT_DATE, which is the database's own
-- day — UTC on Supabase, still yesterday until 8 a.m. in Manila. Only that
-- comparison changes; the function is otherwise as 20261121000100 left it.
CREATE OR REPLACE FUNCTION public.enforce_inventory_movement_scope() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    manila_today date := (now() AT TIME ZONE 'Asia/Manila')::date;
BEGIN
    IF NEW.event_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM inventory i JOIN events e ON e.id = NEW.event_id
        WHERE i.id = NEW.inventory_id AND i.organization_id = e.organization_id
        AND i.department_id IS NOT DISTINCT FROM e.department_id) THEN
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
                AND ex.paid_on <= manila_today AND ex.received_on <= manila_today
                AND r.event_id = ex.event_id AND r.amount = ex.amount
                AND r.review_status IN ('clear','cleared') AND length(trim(r.purpose)) > 0) THEN
            RAISE EXCEPTION 'Purchased stock requires a completed, paid and received, receipted asset transaction';
        END IF;
    END IF;
    RETURN NEW;
END $$;

COMMIT;
