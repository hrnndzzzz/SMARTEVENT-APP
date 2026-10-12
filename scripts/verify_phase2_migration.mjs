// Isolated PostgreSQL migration test: no network, credentials or live data.
// Uses the optional PGlite test installation documented in verify_phase1_migration.mjs.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../tmp/phase1-postgres/node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
const id = (value) => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const rows = async (sql) => (await db.query(sql)).rows;
const denied = async (sql, code = '42501') => assert.rejects(db.query(sql), (error) => error.code === code);
try {
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
    CREATE ROLE smartevent_app NOLOGIN NOBYPASSRLS;
    GRANT USAGE ON SCHEMA public TO smartevent_app;
    CREATE TABLE users (id UUID PRIMARY KEY, role VARCHAR(20), department_id UUID, organization_id UUID);
    CREATE TABLE events (id UUID PRIMARY KEY, status VARCHAR(20));
    INSERT INTO users (id, role) VALUES ('${id(1)}', 'super_admin');
    INSERT INTO events VALUES ('${id(2)}', 'approved'), ('${id(3)}', 'draft');
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;`);
  await db.exec(await readFile(new URL('../supabase/migrations/20261004005904_phase1_institutional_routing_compliance.sql', import.meta.url), 'utf8'));
  await db.exec(`INSERT INTO event_participants (id, event_id, student_number, full_name) VALUES ('${id(4)}', '${id(2)}', 'S1', 'Historical participant');
    INSERT INTO event_requirements (id, event_id, name, phase) VALUES ('${id(5)}', '${id(2)}', 'Historical requirement', 'pre_activity');
    INSERT INTO student_compliance_records (event_id, participant_id, requirement_id, status, reviewed_by, reviewed_at)
      VALUES ('${id(2)}', '${id(4)}', '${id(5)}', 'VERIFIED', '${id(1)}', now());`);
  await db.exec(await readFile(new URL('../supabase/migrations/20261004073859_phase2_pre_activity_compliance.sql', import.meta.url), 'utf8'));
  assert.deepEqual(await rows('SELECT status FROM events ORDER BY id'), [{status: 'approved'}, {status: 'draft'}]);
  assert.deepEqual(await rows('SELECT status, version, notarization_confirmed FROM student_compliance_records'), [{status: 'VERIFIED', version: 1, notarization_confirmed: false}]);
  assert.deepEqual(await rows('SELECT is_active FROM event_participants'), [{is_active: true}]);
  for (const table of ['event_logistics', 'event_personnel', 'event_vehicles', 'event_compliance_documents']) {
    assert.deepEqual(await rows(`SELECT relrowsecurity FROM pg_class WHERE oid = 'public.${table}'::regclass`), [{relrowsecurity: true}]);
    assert.deepEqual(await rows(`SELECT roles, cmd FROM pg_policies WHERE tablename = '${table}'`), [{roles: ['smartevent_app'], cmd: 'ALL'}]);
    for (const role of ['anon', 'authenticated', 'service_role']) {
      await db.exec(`SET ROLE ${role}`);
      await denied(`SELECT * FROM ${table}`);
      await denied(`INSERT INTO ${table} DEFAULT VALUES`);
      await denied(`UPDATE ${table} SET event_id = event_id`);
      await denied(`DELETE FROM ${table}`);
      await db.exec('RESET ROLE');
    }
  }
  await db.exec(`SET ROLE smartevent_app;
    INSERT INTO event_logistics (event_id, activity_location, destination) VALUES ('${id(3)}', 'off_campus', 'Museum');
    INSERT INTO event_personnel (event_id, staff_reference, full_name, position, qualifications)
      VALUES ('${id(3)}', 'EMP1', 'Faculty', 'Professor', 'Experienced supervisor');
    INSERT INTO event_vehicles (id, event_id, plate_number, operator_name, driver_name)
      VALUES ('${id(6)}', '${id(3)}', 'ABC123', 'Carrier', 'Driver');
    INSERT INTO event_compliance_documents (event_id, vehicle_id, document_key, kind, document_url, reference_number, submitted_by)
      VALUES ('${id(3)}', '${id(6)}', '${id(6)}:insurance', 'insurance', 'private-reference', 'POL123', '${id(1)}');`);
  await denied("UPDATE event_logistics SET activity_location = 'unknown'", '23514');
  await denied("UPDATE event_logistics SET transport_mode = 'invented'", '23514');
  await denied('UPDATE student_compliance_records SET version = 0', '23514');
  await denied("UPDATE student_compliance_records SET evidence_mode = 'student_portal'", '23514');
  await denied("UPDATE event_compliance_documents SET status = 'VERIFIED'", '23514');
  await denied(`UPDATE event_compliance_documents SET event_id = '${id(2)}'`, '23503');
  await denied("UPDATE event_compliance_documents SET kind = 'medical_clearance'", '23514');
  await denied(`INSERT INTO event_personnel (event_id, staff_reference, full_name, position, qualifications)
    VALUES ('${id(3)}', 'EMP1', 'Duplicate', 'Professor', 'Experienced')`, '23505');
  await db.exec(`UPDATE event_compliance_documents SET status = 'VERIFIED', reviewed_by = '${id(1)}', reviewed_at = now(), validity_confirmed = true, version = 2;`);
  assert.equal((await rows('SELECT * FROM event_compliance_documents'))[0].version, 2);
  console.log('PASS: Phase 2 migration, historical preservation, constraints, cross-event FKs, RLS and all client/backend grants.');
  if (process.argv.includes('--phase3')) {
    await db.exec('RESET ROLE');
    await db.exec(await readFile(new URL('../supabase/migrations/20261004124658_phase3_execution_and_closure.sql', import.meta.url), 'utf8'));
    assert.deepEqual(await rows('SELECT status, completed_on, completed_at, completed_by FROM events ORDER BY id'), [
      {status: 'approved', completed_on: null, completed_at: null, completed_by: null},
      {status: 'draft', completed_on: null, completed_at: null, completed_by: null},
    ]);
    assert.deepEqual(await rows('SELECT participation_mode FROM event_participants'), [{participation_mode: 'attending'}]);
    assert.deepEqual(await rows("SELECT relrowsecurity FROM pg_class WHERE oid = 'event_parallel_activities'::regclass"), [{relrowsecurity: true}]);
    for (const role of ['anon', 'authenticated', 'service_role']) {
      await db.exec(`SET ROLE ${role}`);
      await denied('SELECT * FROM event_parallel_activities');
      await denied('INSERT INTO event_parallel_activities DEFAULT VALUES');
      await denied('UPDATE event_parallel_activities SET version = version');
      await denied('DELETE FROM event_parallel_activities');
      await db.exec('RESET ROLE');
    }
    await db.exec(`SET ROLE smartevent_app;
      INSERT INTO event_parallel_activities (event_id, participant_id, title, learning_objectives, instructions, reason, assigned_by)
        VALUES ('${id(2)}', '${id(4)}', 'Alternative project', 'Equivalent outcomes', 'Submit reflection', 'Cannot attend', '${id(1)}');`);
    await denied(`UPDATE event_parallel_activities SET event_id = '${id(3)}'`, '23503');
    await denied("UPDATE event_parallel_activities SET status = 'VERIFIED'", '23514');
    await denied('UPDATE event_parallel_activities SET version = 0', '23514');
    await denied("UPDATE event_participants SET participation_mode = 'skip_checks'", '23514');
    await db.exec(`UPDATE event_parallel_activities SET status = 'VERIFIED', reviewed_by = '${id(1)}', reviewed_at = now(), evidence_mode = 'physical';
      INSERT INTO event_compliance_documents (event_id, document_key, kind, document_url, reference_number, submitted_by)
        VALUES ('${id(2)}', 'event:signed_attendance', 'signed_attendance', 'private-reference', 'ATT001', '${id(1)}');`);
    console.log('PASS: Phase 3 migration, preserved approvals, parallel-activity constraints/FKs, closure documents and RLS/client grants.');
  }
} finally { await db.close(); }
