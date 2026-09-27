-- Apply after migrations 001-005; review legacy records before validating checks.
BEGIN;
ALTER TABLE income_records ADD COLUMN IF NOT EXISTS source_type VARCHAR(30) NOT NULL DEFAULT 'other';

CREATE TABLE IF NOT EXISTS receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    department_id UUID NOT NULL REFERENCES departments(id),
    event_id UUID NOT NULL REFERENCES events(id),
    expense_id UUID REFERENCES expenses(id),
    income_id UUID REFERENCES income_records(id),
    purpose TEXT NOT NULL CHECK (length(trim(purpose)) > 0),
    receipt_url TEXT NOT NULL CHECK (receipt_url ~ '^https?://'),
    merchant VARCHAR(150),
    receipt_number VARCHAR(100),
    issued_on DATE NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    url_fingerprint VARCHAR(64) NOT NULL,
    file_sha256 VARCHAR(64),
    reference_key VARCHAR(64),
    is_flagged BOOLEAN NOT NULL DEFAULT FALSE,
    similar_receipt_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    review_status VARCHAR(20) NOT NULL DEFAULT 'clear'
        CHECK (review_status IN ('clear', 'pending', 'cleared', 'rejected')),
    review_reason TEXT,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    recorded_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT receipt_one_transaction CHECK (
        (expense_id IS NOT NULL AND income_id IS NULL) OR (income_id IS NOT NULL AND expense_id IS NULL)),
    CONSTRAINT uq_receipt_expense UNIQUE (expense_id),
    CONSTRAINT uq_receipt_income UNIQUE (income_id),
    CONSTRAINT uq_receipt_url UNIQUE (organization_id, url_fingerprint),
    CONSTRAINT uq_receipt_file UNIQUE (organization_id, file_sha256),
    CONSTRAINT uq_receipt_reference UNIQUE (organization_id, reference_key)
);
CREATE INDEX IF NOT EXISTS ix_receipts_event ON receipts(event_id);
CREATE INDEX IF NOT EXISTS ix_receipts_similarity ON receipts(organization_id, issued_on, amount);
CREATE INDEX IF NOT EXISTS ix_receipts_pending ON receipts(organization_id) WHERE review_status = 'pending';
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

-- API-owned financial evidence cannot be linked to a different event/scope.
CREATE OR REPLACE FUNCTION enforce_receipt_transaction_link() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE linked_event UUID; linked_amount NUMERIC; event_org UUID; event_department UUID;
BEGIN
    IF NEW.expense_id IS NOT NULL THEN
        SELECT event_id, amount INTO linked_event, linked_amount FROM expenses WHERE id = NEW.expense_id;
        IF NOT EXISTS (SELECT 1 FROM expenses WHERE id = NEW.expense_id
                       AND organization_id = NEW.organization_id AND department_id = NEW.department_id) THEN
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
DROP TRIGGER IF EXISTS receipt_transaction_link ON receipts;
CREATE TRIGGER receipt_transaction_link BEFORE INSERT OR UPDATE ON receipts
    FOR EACH ROW EXECUTE FUNCTION enforce_receipt_transaction_link();

CREATE OR REPLACE FUNCTION protect_receipted_transaction() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE has_receipt BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'expenses' THEN
        SELECT EXISTS (SELECT 1 FROM receipts WHERE expense_id = OLD.id) INTO has_receipt;
        IF has_receipt AND (NEW.expense_date IS DISTINCT FROM OLD.expense_date
            OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
            OR NEW.department_id IS DISTINCT FROM OLD.department_id) THEN
            RAISE EXCEPTION 'Receipted expense date and ownership are immutable';
        END IF;
    ELSE
        SELECT EXISTS (SELECT 1 FROM receipts WHERE income_id = OLD.id) INTO has_receipt;
    END IF;
    IF has_receipt AND (NEW.event_id IS DISTINCT FROM OLD.event_id OR NEW.amount IS DISTINCT FROM OLD.amount) THEN
        RAISE EXCEPTION 'Receipted transaction event and amount are immutable';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS protect_receipted_expense ON expenses;
CREATE TRIGGER protect_receipted_expense BEFORE UPDATE ON expenses
    FOR EACH ROW EXECUTE FUNCTION protect_receipted_transaction();
DROP TRIGGER IF EXISTS protect_receipted_income ON income_records;
CREATE TRIGGER protect_receipted_income BEFORE UPDATE ON income_records
    FOR EACH ROW EXECUTE FUNCTION protect_receipted_transaction();

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'income_source_and_purpose_valid'
                   AND conrelid = 'income_records'::regclass) THEN
        ALTER TABLE income_records ADD CONSTRAINT income_source_and_purpose_valid CHECK (
            length(trim(source)) > 0 AND length(trim(purpose)) > 0 AND amount > 0
            AND source_type IN ('registration_fees', 'sponsorship', 'donation', 'other')
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'expense_purpose_valid'
                   AND conrelid = 'expenses'::regclass) THEN
        ALTER TABLE expenses ADD CONSTRAINT expense_purpose_valid CHECK (
            length(trim(description)) > 0 AND amount > 0 AND (receipt_url IS NULL OR event_id IS NOT NULL)
        ) NOT VALID;
    END IF;
END $$;
COMMIT;

-- Repair invalid legacy purposes, amounts, sources, and event assignments first.
-- ALTER TABLE income_records VALIDATE CONSTRAINT income_source_and_purpose_valid;
-- ALTER TABLE expenses VALIDATE CONSTRAINT expense_purpose_valid;
-- Legacy receipt URLs remain in expenses; import metadata from actual receipts,
-- rather than inventing receipt numbers/merchants or financial records.
