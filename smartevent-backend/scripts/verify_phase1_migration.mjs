// Isolated PostgreSQL smoke test. No DATABASE_URL, network or live data is used.
// Setup: npm install --prefix tmp/phase1-postgres --no-save --package-lock=false --ignore-scripts @electric-sql/pglite@0.5.8
// Run: node scripts/verify_phase1_migration.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../tmp/phase1-postgres/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const migration = await readFile(new URL('../supabase/migrations/20261004005904_phase1_institutional_routing_compliance.sql', import.meta.url), 'utf8');
const tables = ['document_routing', 'requirement_presets', 'event_participants', 'event_requirements', 'student_compliance_records'];
const id = (value) => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
const denied = async (sql, code = '42501') => assert.rejects(db.query(sql), (error) => error.code === code);

try {
  // Minimal pre-Phase-1 baseline, including legacy checks to be replaced.
  // This is not a rehearsal of all historical migrations or Supabase Storage.
  await db.exec(`
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role BYPASSRLS;
    CREATE TABLE public.users (
      id UUID PRIMARY KEY, role VARCHAR(20) NOT NULL,
      department_id UUID, organization_id UUID,
      CONSTRAINT users_role_check CHECK (role IN ('super_admin', 'admin', 'adviser', 'treasurer', 'officer', 'sds_staff')),
      CONSTRAINT users_role_scope_check CHECK (
        (role IN ('super_admin', 'sds_staff') AND department_id IS NULL AND organization_id IS NULL)
        OR (role IN ('admin', 'adviser', 'treasurer', 'officer') AND department_id IS NOT NULL AND organization_id IS NOT NULL)
      )
    );
    CREATE TABLE public.events (
      id UUID PRIMARY KEY, status VARCHAR(20) NOT NULL,
      CONSTRAINT legacy_event_status CHECK (status IN ('draft', 'pending', 'pending_adviser', 'pending_admin', 'approved', 'rejected', 'completed'))
    );
    INSERT INTO public.events VALUES ('${id(1)}', 'approved'), ('${id(2)}', 'draft');
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
  `);
  await assert.rejects(db.exec(migration), /Apply scripts\/008_security_hardening.sql/);
  await db.exec('ROLLBACK; CREATE ROLE smartevent_app NOLOGIN NOBYPASSRLS; GRANT USAGE ON SCHEMA public TO smartevent_app;');
  await db.exec(migration);

  assert.deepEqual(await rows('SELECT status, review_round FROM events ORDER BY id'), [
    { status: 'approved', review_round: 1 }, { status: 'draft', review_round: 1 },
  ]);
  await db.query("UPDATE events SET status = 'pending_institutional_review' WHERE id = $1", [id(2)]);
  await denied("UPDATE events SET status = 'invented'", '23514');
  await denied('UPDATE events SET review_round = 0', '23514');
  await db.query("INSERT INTO users (id, role) VALUES ($1, 'signatory')", [id(3)]);
  await denied(`INSERT INTO users VALUES ('${id(4)}', 'signatory', '${id(9)}', '${id(9)}')`, '23514');
  await denied(`INSERT INTO users (id, role) VALUES ('${id(4)}', 'invented')`, '23514');
  assert.deepEqual(await rows('SELECT code, phase, requires_notarization, is_sensitive FROM requirement_presets ORDER BY code'), [
    { code: 'medical_clearance', phase: 'pre_activity', requires_notarization: false, is_sensitive: true },
    { code: 'parent_guardian_consent', phase: 'pre_activity', requires_notarization: true, is_sensitive: false },
    { code: 'student_learning_journal', phase: 'post_activity', requires_notarization: false, is_sensitive: false },
  ]);

  for (const table of tables) {
    assert.deepEqual(await rows('SELECT relrowsecurity FROM pg_class WHERE oid = $1::regclass', [`public.${table}`]), [{ relrowsecurity: true }]);
    const policies = await rows("SELECT roles, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename = $1", [table]);
    assert.deepEqual(policies, [{ roles: ['smartevent_app'], cmd: 'ALL' }]);
    for (const role of ['anon', 'authenticated', 'service_role']) {
      await db.exec(`SET ROLE ${role}`);
      await denied(`SELECT * FROM public.${table}`);
      await denied(`INSERT INTO public.${table} DEFAULT VALUES`);
      await denied(`UPDATE public.${table} SET id = id`);
      await denied(`DELETE FROM public.${table}`);
      await db.exec('RESET ROLE');
    }
  }

  await db.exec('SET ROLE smartevent_app');
  assert.equal((await rows('SELECT * FROM requirement_presets')).length, 3);
  await denied('INSERT INTO requirement_presets DEFAULT VALUES');
  await denied("UPDATE requirement_presets SET name = 'changed'");
  await denied('DELETE FROM requirement_presets');
  await db.exec(`
    INSERT INTO document_routing (id, event_id, step_order, signatory_id)
      VALUES ('${id(10)}', '${id(2)}', 1, '${id(3)}');
    INSERT INTO event_participants (id, event_id, student_number, full_name)
      VALUES ('${id(11)}', '${id(1)}', '2026-001', 'Test Participant'),
             ('${id(12)}', '${id(2)}', '2026-001', 'Test Participant');
    INSERT INTO event_requirements (id, event_id, name, phase)
      VALUES ('${id(13)}', '${id(1)}', 'Consent', 'pre_activity'),
             ('${id(14)}', '${id(2)}', 'Consent', 'pre_activity');
    INSERT INTO student_compliance_records (event_id, participant_id, requirement_id)
      VALUES ('${id(1)}', '${id(11)}', '${id(13)}');
  `);
  assert.deepEqual(await rows('SELECT status FROM student_compliance_records'), [{ status: 'MISSING' }]);
  await denied(`INSERT INTO student_compliance_records (event_id, participant_id, requirement_id)
    VALUES ('${id(1)}', '${id(11)}', '${id(14)}')`, '23503');
  await denied(`INSERT INTO student_compliance_records (event_id, participant_id, requirement_id)
    VALUES ('${id(2)}', '${id(11)}', '${id(14)}')`, '23503');
  await denied(`INSERT INTO student_compliance_records (event_id, participant_id, requirement_id)
    VALUES ('${id(1)}', '${id(11)}', '${id(13)}')`, '23505');
  await denied("UPDATE student_compliance_records SET status = 'CLEARED'", '23514');
  await denied("UPDATE student_compliance_records SET status = 'VERIFIED'", '23514');
  await db.exec(`UPDATE student_compliance_records SET status = 'VERIFIED', reviewed_by = '${id(3)}', reviewed_at = now()`);
  await denied(`INSERT INTO event_participants (event_id, student_number, full_name)
    VALUES ('${id(1)}', '2026-001', 'Duplicate')`, '23505');
  await denied(`INSERT INTO document_routing (event_id, step_order, signatory_id)
    VALUES ('${id(2)}', 1, '${id(3)}')`, '23505');
  await denied("UPDATE document_routing SET status = 'approved'", '23514');
  await db.exec("UPDATE document_routing SET status = 'approved', decided_at = now()");
  await db.exec(`INSERT INTO document_routing (event_id, review_round, step_order, signatory_id)
    VALUES ('${id(2)}', 2, 1, '${id(3)}')`);
  assert.equal((await rows('SELECT * FROM document_routing')).length, 2);
  await db.exec(`DELETE FROM document_routing WHERE review_round = 2;
    DELETE FROM student_compliance_records;
    DELETE FROM event_requirements;
    DELETE FROM event_participants; RESET ROLE;`);
  console.log('PASS: Phase 1 migration, legacy preservation, presets, constraints, RLS and backend/client grants.');
} finally {
  await db.close();
}
