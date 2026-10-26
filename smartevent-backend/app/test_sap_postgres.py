"""Opt-in PostgreSQL migration/locking checks in a disposable test database.

Set SAP_TEST_POSTGRES_URL explicitly; never falls back to DATABASE_URL.
Creates and removes only uniquely named sap_test_* schemas.
"""
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event as ThreadEvent
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.database import Base
from app.models import Department, Organization, User, Event, Notification
from app.models_sap import SAPProposal, SAPRevision, SAPReview
from app.routers.sap import review_notes
from app.schemas_sap import ReviewNotesWrite
from app.services import sap


@pytest.fixture
def pg_sandbox():
    url = os.environ.get('SAP_TEST_POSTGRES_URL')
    if not url:
        pytest.skip('Set SAP_TEST_POSTGRES_URL to a disposable PostgreSQL test database')
    parsed = make_url(url)
    if parsed.get_backend_name() != 'postgresql' or not (parsed.database or '').endswith('_test'):
        pytest.fail('SAP_TEST_POSTGRES_URL must be PostgreSQL with a database name ending in _test')
    schema = 'sap_test_' + uuid4().hex
    owner = create_engine(url)
    with owner.begin() as conn:
        conn.execute(text(f'CREATE SCHEMA "{schema}"'))
    engine = create_engine(url, connect_args={'options': f'-csearch_path={schema} -clock_timeout=5000 -cstatement_timeout=15000'})
    try:
        yield engine, schema
    finally:
        engine.dispose()
        # The identifier is generated above, never supplied by a caller.
        with owner.begin() as conn:
            conn.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        owner.dispose()


def test_notification_migration_preserves_rows_and_table_access(pg_sandbox):
    engine, schema = pg_sandbox
    with engine.begin() as conn:
        conn.execute(text('CREATE TABLE notifications (id integer primary key, body text)'))
        conn.execute(text("INSERT INTO notifications VALUES (1, 'Existing notification')"))
        conn.execute(text('ALTER TABLE notifications ENABLE ROW LEVEL SECURITY'))
        before = conn.execute(text("SELECT relacl, relrowsecurity FROM pg_class WHERE oid = 'notifications'::regclass")).one()
        migration = next((Path(__file__).parents[1] / 'supabase/migrations').glob('*_sap_notification_payload.sql')).read_text()
        sql = migration.replace('BEGIN;', '').replace('COMMIT;', '').replace('public.notifications', f'"{schema}".notifications')
        conn.exec_driver_sql(sql)
        assert conn.execute(text('SELECT body, payload FROM notifications WHERE id=1')).one() == ('Existing notification', None)
        assert conn.execute(text("SELECT relacl, relrowsecurity FROM pg_class WHERE oid = 'notifications'::regclass")).one() == before
        conn.execute(text('UPDATE notifications SET payload = CAST(:value AS jsonb) WHERE id=1'),
                     {'value': '{"event_id":"test","state":"draft"}'})
        assert conn.execute(text('SELECT payload FROM notifications WHERE id=1')).scalar_one()['state'] == 'draft'


@pytest.mark.parametrize('first', ['withdraw', 'review'])
def test_review_and_withdrawal_serialize_on_parent_event(pg_sandbox, first):
    engine, _ = pg_sandbox
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        dept = Department(code='TEST', name='Test department')
        db.add(dept)
        db.flush()
        org = Organization(code='TEST', name='Test organization', department_id=dept.id)
        db.add(org)
        db.flush()
        owner = User(full_name='Proposer', email='proposer@example.invalid', password_hash='unused',
                     role='treasurer', department_id=dept.id, organization_id=org.id)
        sds = User(full_name='SDS', email='sds@example.invalid', password_hash='unused', role='sds_staff')
        db.add_all([owner, sds])
        db.flush()
        event = Event(title='Concurrency test', proposed_by=owner.id, organization_id=org.id,
                      department_id=dept.id, status='pending_institutional_review')
        db.add(event)
        db.flush()
        proposal = SAPProposal(event_id=event.id, state='pending_sap_review', version=1, revision_no=1)
        db.add(proposal)
        db.flush()
        db.add(SAPRevision(proposal_id=proposal.id, revision_no=1, snapshot={}, printable_pdf=b'%PDF-test',
                           pdf_sha256='a' * 64, verification_token='test-token', submitted_by=owner.id))
        db.commit()
        ids = (event.id, owner.id, sds.id)
    event_id, owner_id, sds_id = ids
    entered, pid_ready = ThreadEvent(), ThreadEvent()
    waiting_pid = []

    def second_action():
        with Session(engine) as db:
            waiting_pid.append(db.execute(text('SELECT pg_backend_pid()')).scalar_one())
            pid_ready.set()
            actor = db.get(User, sds_id if first == 'withdraw' else owner_id)
            entered.set()
            try:
                if first == 'withdraw':
                    review_notes(event_id, ReviewNotesWrite(expected_version=1, overall_remarks='Review'), db, actor)
                else:
                    ev, prop = sap.load(db, event_id, actor, write=True, proposer=True)
                    sap.check_version(prop, 1)
                    sap.withdraw(db, ev, prop, actor)
                return 200
            except HTTPException as exc:
                db.rollback()
                return exc.status_code

    with ThreadPoolExecutor(max_workers=1) as executor, Session(engine) as db:
        actor = db.get(User, owner_id if first == 'withdraw' else sds_id)
        ev, prop = sap.load(db, event_id, actor, write=True,
                            proposer=first == 'withdraw', sds=first == 'review')
        winner_pid = db.execute(text('SELECT pg_backend_pid()')).scalar_one()
        future = executor.submit(second_action)
        assert pid_ready.wait(5) and entered.wait(5)
        # Observe a real PostgreSQL lock wait, rather than relying on a sleep.
        from time import monotonic, sleep
        deadline = monotonic() + 3
        blocked = False
        with engine.connect() as observer:
            while monotonic() < deadline:
                blockers = observer.execute(text('SELECT pg_blocking_pids(:pid)'), {'pid': waiting_pid[0]}).scalar_one()
                if winner_pid in blockers:
                    blocked = True
                    break
                sleep(0.02)
        if not blocked:
            db.rollback()
            pytest.fail('Competing action did not wait on the parent event lock')
        if first == 'withdraw':
            sap.withdraw(db, ev, prop, actor)
        else:
            review_notes(event_id, ReviewNotesWrite(expected_version=1, overall_remarks='First review'), db, actor)
        assert future.result(timeout=8) == 409
    with Session(engine) as db:
        assert db.query(SAPProposal).one().state == ('draft' if first == 'withdraw' else 'pending_sap_review')
        assert db.query(SAPReview).count() == (0 if first == 'withdraw' else 1)
        assert db.query(Notification).count() == (2 if first == 'withdraw' else 0)
