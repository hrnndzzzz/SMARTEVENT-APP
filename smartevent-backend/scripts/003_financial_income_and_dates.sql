-- Add actual event income records and a consistent financial date for expenses.

ALTER TABLE expenses
    ADD COLUMN IF NOT EXISTS expense_date DATE;

UPDATE expenses
SET expense_date = COALESCE(ocr_date, created_at::date, CURRENT_DATE)
WHERE expense_date IS NULL;

ALTER TABLE expenses
    ALTER COLUMN expense_date SET DEFAULT CURRENT_DATE,
    ALTER COLUMN expense_date SET NOT NULL;

CREATE TABLE IF NOT EXISTS income_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id),
    source VARCHAR(100) NOT NULL,
    purpose TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    received_on DATE NOT NULL DEFAULT CURRENT_DATE,
    recorded_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_income_records_event_received_on
    ON income_records(event_id, received_on);