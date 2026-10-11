-- Apply after 001-006. Back up first and test the workflow on staging PostgreSQL.
-- This migration preserves quantities/history; it does not invent legacy events
-- or replay asset purchases that were already converted by the older workflow.
BEGIN;
ALTER TABLE inventory ADD COLUMN IF NOT EXISTS event_id UUID REFERENCES events(id);
ALTER TABLE expense_items ADD COLUMN IF NOT EXISTS quantity INTEGER NOT NULL DEFAULT 1;
ALTER TABLE expense_items ADD COLUMN IF NOT EXISTS unit VARCHAR(30) NOT NULL DEFAULT 'pcs';
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS purchase_completed_at TIMESTAMPTZ;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS paid_on DATE;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS received_on DATE;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS payment_reference VARCHAR(150);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS purchase_vendor VARCHAR(150);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2);
ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS transaction_type VARCHAR(30) NOT NULL DEFAULT 'legacy';
ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS expense_item_id UUID REFERENCES expense_items(id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_purchase_line ON inventory_transactions(expense_item_id)
    WHERE expense_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_inventory_event ON inventory(event_id);
CREATE INDEX IF NOT EXISTS ix_inventory_transaction_event_type ON inventory_transactions(inventory_id, event_id, transaction_type);

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='inventory_event_and_stock_valid' AND conrelid='inventory'::regclass) THEN
        ALTER TABLE inventory ADD CONSTRAINT inventory_event_and_stock_valid CHECK (
            event_id IS NOT NULL AND quantity >= 0 AND quantity = trunc(quantity)
            AND length(trim(unit)) > 0 AND length(trim(item_name)) > 0
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='inventory_movement_metadata_valid' AND conrelid='inventory_transactions'::regclass) THEN
        ALTER TABLE inventory_transactions ADD CONSTRAINT inventory_movement_metadata_valid CHECK (
            event_id IS NOT NULL AND reason IS NOT NULL AND length(trim(reason)) > 0
            AND change_qty <> 0 AND change_qty = trunc(change_qty)
            AND transaction_type IN ('opening_balance','acquisition','donation','purchase','issue','return','disposal','adjustment')
            AND (transaction_type NOT IN ('opening_balance','acquisition','donation','purchase','return') OR change_qty > 0)
            AND (transaction_type NOT IN ('issue','disposal') OR change_qty < 0)
            AND ((transaction_type = 'purchase' AND expense_item_id IS NOT NULL)
                OR (transaction_type <> 'purchase' AND expense_item_id IS NULL))
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='expense_item_quantity_valid' AND conrelid='expense_items'::regclass) THEN
        ALTER TABLE expense_items ADD CONSTRAINT expense_item_quantity_valid CHECK (
            quantity > 0 AND length(trim(unit)) > 0
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_completion_details_valid' AND conrelid='expenses'::regclass) THEN
        ALTER TABLE expenses ADD CONSTRAINT purchase_completion_details_valid CHECK (
            purchase_completed_at IS NULL OR (status = 'approved' AND event_id IS NOT NULL
                AND paid_on IS NOT NULL AND received_on IS NOT NULL
                AND paid_amount IS NOT NULL AND paid_amount = amount
                AND payment_method IS NOT NULL AND payment_method IN ('cash','bank_transfer','card','other')
                AND payment_reference IS NOT NULL AND length(trim(payment_reference)) > 0
                AND purchase_vendor IS NOT NULL AND length(trim(purchase_vendor)) > 0)
        ) NOT VALID;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION enforce_inventory_event_scope() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.event_id IS NULL OR NOT EXISTS (SELECT 1 FROM events e WHERE e.id = NEW.event_id
        AND e.organization_id = NEW.organization_id AND e.department_id = NEW.department_id) THEN
        RAISE EXCEPTION 'Inventory requires an event in the same organization and department';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.event_id IS NOT NULL AND NEW.event_id IS DISTINCT FROM OLD.event_id THEN
            RAISE EXCEPTION 'Initial inventory event is immutable';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION enforce_inventory_movement_scope() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM inventory i JOIN events e ON e.id = NEW.event_id
        WHERE i.id = NEW.inventory_id AND i.organization_id = e.organization_id
        AND i.department_id = e.department_id AND i.event_id IS NOT NULL) THEN
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
                AND ex.department_id = i.department_id AND ex.paid_amount = ex.amount
                AND ex.paid_on <= CURRENT_DATE AND ex.received_on <= CURRENT_DATE
                AND r.event_id = ex.event_id AND r.amount = ex.amount
                AND r.review_status IN ('clear','cleared') AND length(trim(r.purpose)) > 0) THEN
            RAISE EXCEPTION 'Purchased stock requires a completed, paid and received, receipted asset transaction';
        END IF;
    END IF;
    RETURN NEW;
END $$;

-- Create missing guards without dropping any existing trigger objects.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='inventory_event_scope_guard' AND tgrelid='inventory'::regclass) THEN
        CREATE TRIGGER inventory_event_scope_guard BEFORE INSERT OR UPDATE ON inventory
            FOR EACH ROW EXECUTE FUNCTION enforce_inventory_event_scope();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='inventory_movement_scope_guard' AND tgrelid='inventory_transactions'::regclass) THEN
        CREATE TRIGGER inventory_movement_scope_guard BEFORE INSERT OR UPDATE ON inventory_transactions
            FOR EACH ROW EXECUTE FUNCTION enforce_inventory_movement_scope();
    END IF;
END $$;
COMMIT;

-- After administrators repair real event links and classify historical movements:
-- ALTER TABLE inventory VALIDATE CONSTRAINT inventory_event_and_stock_valid;
-- ALTER TABLE inventory_transactions VALIDATE CONSTRAINT inventory_movement_metadata_valid;
-- ALTER TABLE expense_items VALIDATE CONSTRAINT expense_item_quantity_valid;
-- ALTER TABLE expenses VALIDATE CONSTRAINT purchase_completion_details_valid;
-- ALTER TABLE inventory ALTER COLUMN event_id SET NOT NULL;
-- ALTER TABLE inventory_transactions ALTER COLUMN event_id SET NOT NULL;
-- Do not guess legacy purchase completion/payment dates or confirmed quantities.
