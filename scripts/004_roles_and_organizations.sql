-- Apply after migrations 001-003 in Supabase SQL Editor before deploying.
-- Existing department-scoped records receive a migration organization for
-- that department. Review these assignments before creating multiple student
-- organizations within a department. Rows without a department stay unassigned.
BEGIN;

CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES departments(id),
    code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, department_id)
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE cite_members ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE categories ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE events ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE inventory ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id);

INSERT INTO organizations (code, name, department_id)
SELECT 'LEGACY-' || left(replace(id::text, '-', ''), 22), name || ' organization', id
FROM departments
ON CONFLICT (code) DO NOTHING;

DO $$
DECLARE table_name text; constraint_name text; role_att smallint; c record;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['users', 'cite_members', 'categories', 'events', 'expenses', 'inventory']
    LOOP
        EXECUTE format(
            'UPDATE %I t SET organization_id = o.id FROM organizations o
             WHERE t.organization_id IS NULL AND t.department_id = o.department_id
             AND o.code = ''LEGACY-'' || left(replace(o.department_id::text, ''-'', ''''), 22)',
            table_name);
        IF table_name = 'users' THEN
            UPDATE users SET organization_id = NULL, department_id = NULL
            WHERE role IN ('super_admin', 'sds_staff');
        END IF;
        constraint_name := table_name || '_organization_department_fk';
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = constraint_name AND conrelid = table_name::regclass) THEN
            EXECUTE format(
                'ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (organization_id, department_id)
                 REFERENCES organizations(id, department_id) NOT VALID', table_name, constraint_name);
        END IF;
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (organization_id, department_id)',
            'idx_' || table_name || '_organization_scope', table_name);
    END LOOP;

    -- Replace any legacy three-role check, preserving unrelated checks.
    SELECT attnum INTO role_att FROM pg_attribute WHERE attrelid = 'users'::regclass AND attname = 'role';
    FOR c IN SELECT conname FROM pg_constraint WHERE conrelid = 'users'::regclass
        AND contype = 'c' AND conkey = ARRAY[role_att]::smallint[]
    LOOP
        EXECUTE format('ALTER TABLE users DROP CONSTRAINT %I', c.conname);
    END LOOP;
    ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (
        role IN ('super_admin', 'admin', 'adviser', 'treasurer', 'officer', 'sds_staff')
    ) NOT VALID;

    -- Catalog names are unique within an organization, not across the school.
    FOR c IN SELECT conrelid::regclass AS table_name, conname FROM pg_constraint p
        WHERE p.contype = 'u' AND p.conrelid IN ('categories'::regclass, 'inventory'::regclass)
        AND cardinality(p.conkey) = 1 AND EXISTS (
            SELECT 1 FROM pg_attribute a WHERE a.attrelid = p.conrelid AND a.attnum = p.conkey[1]
            AND a.attname IN ('name', 'item_name'))
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', c.table_name, c.conname);
    END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_category_organization_name ON categories (organization_id, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_organization_name ON inventory (organization_id, lower(item_name));
CREATE INDEX IF NOT EXISTS idx_audit_organization_created ON audit_logs (organization_id, created_at DESC);

-- NOT VALID preserves legacy unassigned rows for administrator repair, while
-- these checks apply immediately to all inserts and updated rows.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_role_scope_check' AND conrelid = 'users'::regclass) THEN
        ALTER TABLE users ADD CONSTRAINT users_role_scope_check CHECK (
            (role IN ('super_admin', 'sds_staff') AND department_id IS NULL AND organization_id IS NULL)
            OR (role IN ('admin', 'adviser', 'treasurer', 'officer') AND department_id IS NOT NULL AND organization_id IS NOT NULL)
        ) NOT VALID;
    END IF;
END $$;
COMMIT;
