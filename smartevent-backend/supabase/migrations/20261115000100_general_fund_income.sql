BEGIN;

-- Income need not belong to an event: membership dues and other general-fund
-- money are recorded against the organization itself. Such a row carries its
-- own scope and academic labels; event income keeps taking them from its event.
ALTER TABLE public.income_records ALTER COLUMN event_id DROP NOT NULL;
ALTER TABLE public.income_records
    ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id),
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES public.departments(id),
    ADD COLUMN IF NOT EXISTS school_year VARCHAR(9),
    ADD COLUMN IF NOT EXISTS semester VARCHAR(10);

ALTER TABLE public.income_records ADD CONSTRAINT income_event_or_general_fund CHECK (
    (event_id IS NOT NULL AND organization_id IS NULL AND department_id IS NULL
        AND school_year IS NULL AND semester IS NULL)
    OR (event_id IS NULL AND organization_id IS NOT NULL
        AND school_year ~ '^[0-9]{4}-[0-9]{4}$' AND semester IN ('1st', '2nd', 'summer'))
);

-- A general-fund row's department is its organization's own.
CREATE TRIGGER income_records_organization_department
    BEFORE INSERT OR UPDATE OF organization_id, department_id ON public.income_records
    FOR EACH ROW EXECUTE FUNCTION public.enforce_organization_department();

CREATE INDEX IF NOT EXISTS ix_income_records_general_fund
    ON public.income_records (organization_id, received_on) WHERE event_id IS NULL;

-- Two new kinds of source.
ALTER TABLE public.income_records DROP CONSTRAINT IF EXISTS income_source_and_purpose_valid;
ALTER TABLE public.income_records ADD CONSTRAINT income_source_and_purpose_valid CHECK (
    length(trim(source)) > 0 AND length(trim(purpose)) > 0 AND amount > 0
    AND source_type IN ('registration_fees', 'sponsorship', 'donation',
                        'membership_dues', 'fundraising', 'other')
) NOT VALID;

COMMIT;
