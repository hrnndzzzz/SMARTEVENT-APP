BEGIN;

-- Stock need not belong to an event: things are lent out, broken in storage or
-- donated between events. An item or movement with an event still has to share
-- the item's organization and department, and a recorded event stays immutable.
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_event_and_stock_valid;
ALTER TABLE public.inventory ADD CONSTRAINT inventory_event_and_stock_valid CHECK (
    quantity >= 0 AND quantity = trunc(quantity)
    AND length(trim(unit)) > 0 AND length(trim(item_name)) > 0
) NOT VALID;

ALTER TABLE public.inventory_transactions DROP CONSTRAINT IF EXISTS inventory_movement_metadata_valid;
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_movement_metadata_valid CHECK (
    reason IS NOT NULL AND length(trim(reason)) > 0
    AND change_qty <> 0 AND change_qty = trunc(change_qty)
    AND transaction_type IN ('opening_balance','acquisition','donation','purchase','issue','return','disposal','adjustment')
    AND (transaction_type NOT IN ('opening_balance','acquisition','donation','purchase','return') OR change_qty > 0)
    AND (transaction_type NOT IN ('issue','disposal') OR change_qty < 0)
    AND ((transaction_type = 'purchase' AND expense_item_id IS NOT NULL)
        OR (transaction_type <> 'purchase' AND expense_item_id IS NULL))
) NOT VALID;

CREATE OR REPLACE FUNCTION public.enforce_inventory_event_scope() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
    IF NEW.event_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM events e WHERE e.id = NEW.event_id
        AND e.organization_id = NEW.organization_id AND e.department_id IS NOT DISTINCT FROM NEW.department_id) THEN
        RAISE EXCEPTION 'Inventory event must be in the same organization and department';
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
                AND ex.paid_on <= CURRENT_DATE AND ex.received_on <= CURRENT_DATE
                AND r.event_id = ex.event_id AND r.amount = ex.amount
                AND r.review_status IN ('clear','cleared') AND length(trim(r.purpose)) > 0) THEN
            RAISE EXCEPTION 'Purchased stock requires a completed, paid and received, receipted asset transaction';
        END IF;
    END IF;
    RETURN NEW;
END $$;

COMMIT;
