-- Apply after 001-008. The roster now holds every self-registering role
-- (Super Admin stays out of it), and the live check had drifted to only
-- officer/adviser, which rejected treasurer rows.
BEGIN;

ALTER TABLE cite_members DROP CONSTRAINT IF EXISTS cite_members_role_check;
ALTER TABLE cite_members ADD CONSTRAINT cite_members_role_check CHECK (
    role IN ('officer', 'adviser', 'treasurer', 'admin', 'sds_staff', 'signatory')
);

COMMIT;
