"""Isolated SAP workflow, security, paper evidence and generic routing regression."""
from copy import deepcopy
from datetime import date
from io import BytesIO
from pathlib import Path
import pytest
from pypdf import PdfReader
from fastapi import HTTPException
from app.test_access_management import system
from app.config import settings
from app.models import DocumentRouting, Notification
from app.models_sap import SAPRevision, SAPFinalCopy
from app.schemas_sap import validate_submission
from app.services.sap_pdf import render_proposal, SLOTS


def fixture_data():
    return dict(details=dict(title='Hack the Future', organization_name='ACPES', school_year='2026-2027',
        department_type='College', department='CITE', course='BSCpE', proposal_date='2026-09-26',
        activity_date='2026-10-28', start_time='08:00:00', end_time='11:00:00', setting='online', modality='online',
        venue='Online conference', persons_in_charge='ACPES officers', attire='School uniform',
        activity_types=['Seminar'], scope='organizational', expected_students=145, program_types=['Academic'],
        rationale='Cybersecurity awareness and responsible ethical hacking.', objectives='Understand digital safety.',
        core_values=['courage', 'community_oriented'], egas=[1, 3], emergency_plan='Contact the assigned staff.',
        total_budget='2500.00', funding_source='Organization funds', additional_information='',
        excuse_arrangement='Provide letters to affected professors.'),
        collections={'program-flow': [dict(start='08:00:00', end='11:00:00', activity='Seminar')],
            'budget-items': [dict(particulars='Speaker', amount='2000.00'), dict(particulars='Certificate', amount='300.00'), dict(particulars='Materials', amount='200.00')],
            'support-requests': [], 'affected-classes': [
                dict(year_level='BSCpE 3', subject='Computer engineering', class_date='2026-10-28', start='07:00:00', end='12:00:00', professor='Professor A'),
                dict(year_level='BSCpE 4', subject='Professional elective', class_date='2026-10-28', start='10:00:00', end='12:00:00', professor='Professor B')]},
        clearance=dict(parents_consent='not_applicable', parents_consent_reason='Online activity', attachments='Program and budget',
            class_interruption='yes', class_interruption_remarks='Excuse letters required', medical_exam='not_applicable', medical_exam_reason='Online activity',
            report_of_compliance='not_applicable', report_of_compliance_reason='No off-campus travel', student_personnel_ratio='145:3'))


@pytest.fixture
def sap_system(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    event = resources[0]['events']
    event.status, event.allocated_budget, event.remaining_budget = 'draft', 2500, 2500
    db.commit()
    monkeypatch.setattr(settings, 'sap_verification_base_url', 'https://example.org/sap/verify')
    login('treasurer')
    base = f'/events/{event.id}/sap-proposal'
    assert client.post(base).status_code == 201
    return client, db, users, event, login, base


def version(client, base):
    response = client.get(base)
    assert response.status_code == 200, response.text
    return response.json()['version']


def populate(ctx, data=None):
    client, db, users, event, login, base = ctx
    data = data or fixture_data()
    login('treasurer')
    result = client.patch(base, json={'expected_version': version(client, base), 'details': data['details']})
    assert result.status_code == 200, result.text
    for key, items in data['collections'].items():
        result = client.put(base + '/' + key, json={'expected_version': version(client, base), 'items': items})
        assert result.status_code == 200, result.text
    login('sds_staff')
    result = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': data['clearance']})
    assert result.status_code == 200, result.text
    login('treasurer')
    result = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert result.status_code == 200, result.text
    return result.json()


def checkpoint(ctx, slot):
    client, db, users, event, login, base = ctx
    login('sds_staff')
    workflow = client.get(base + '/workflow').json()
    row = workflow['steps'][slot - 1]
    return client.post(base + f"/workflow/{row['id']}/record", json={
        'expected_version': workflow['version'], 'signer_name': users['treasurer'].full_name if slot == 1 else f'Physical signer {slot}',
        'signer_reference': f'institution-person-{slot}', 'assigned_user_id': str(users['treasurer'].id) if slot == 1 else None,
        'physical_signature_date': date.today().isoformat(), 'remarks': 'SDS checked the paper', 'recorded_on_behalf': True})


def test_six_page_clean_print_and_nine_slots():
    data = fixture_data()
    pdf = render_proposal(data, 1, 'https://example.org/sap/verify/test-token')
    reader = PdfReader(BytesIO(pdf))
    assert len(reader.pages) == 6
    text = '\n'.join(page.extract_text() for page in reader.pages)
    assert '145' in text and '2500.00' in text and 'SAS-SDS-FO-020' in text
    for slot, (position, label) in enumerate(SLOTS, 1):
        assert f'{slot}. {label}' in text
    assert 'Scan to verify' in text and len(reader.pages[5].get_contents().get_data()) > 5000
    assert all(not page.images for page in reader.pages)  # No scanned marks/background.
    assert 'Date Forwarded' not in text


@pytest.mark.parametrize('case', ['budget', 'end', 'program', 'class', 'offcampus', 'na', 'interruption'])
def test_validation_rejects_invalid_aggregate(case):
    data = fixture_data()
    if case == 'budget': data['details']['total_budget'] = '2500.01'
    if case == 'end': data['details']['end_time'] = '07:00:00'
    if case == 'program': data['collections']['program-flow'][0]['end'] = '12:00:00'
    if case == 'class': data['collections']['affected-classes'][0]['end'] = '00:00:00'
    if case == 'offcampus': data['details']['setting'] = 'off_campus'
    if case == 'na': data['clearance']['medical_exam_reason'] = ''
    if case == 'interruption': data['clearance']['class_interruption'] = 'none'
    with pytest.raises(ValueError):
        validate_submission(data['details'], data['collections'], data['clearance'])


def test_permission_and_stale_version(sap_system):
    client, db, users, event, login, base = sap_system
    current = version(client, base)
    assert client.put(base + '/sds-clearance', json={'expected_version': current, 'clearance': fixture_data()['clearance']}).status_code == 403
    login('admin')
    assert client.patch(base, json={'expected_version': current, 'details': fixture_data()['details']}).status_code == 403
    login('sds_staff')
    assert client.patch(base, json={'expected_version': current, 'details': fixture_data()['details']}).status_code == 403
    login('treasurer')
    assert client.patch(base, json={'expected_version': current + 1, 'details': fixture_data()['details']}).status_code == 409
    login('officer')
    assert client.patch(base, json={'expected_version': current, 'details': fixture_data()['details']}).status_code == 403


def test_parallel_moderators_and_order(sap_system):
    populate(sap_system)
    assert checkpoint(sap_system, 4).status_code == 409
    assert checkpoint(sap_system, 1).status_code == 200
    assert checkpoint(sap_system, 3).status_code == 200
    assert checkpoint(sap_system, 4).status_code == 409
    assert checkpoint(sap_system, 2).status_code == 200
    assert checkpoint(sap_system, 4).status_code == 200
    assert checkpoint(sap_system, 4).status_code == 409


def test_proposer_cannot_review(sap_system):
    populate(sap_system)
    checkpoint(sap_system, 1)
    client, db, users, event, login, base = sap_system
    workflow = client.get(base + '/workflow').json()
    response = client.post(base + f"/workflow/{workflow['steps'][1]['id']}/record", json={
        'expected_version': workflow['version'], 'signer_name': users['treasurer'].full_name,
        'signer_reference': 'different', 'assigned_user_id': str(users['treasurer'].id), 'physical_signature_date': date.today().isoformat()})
    assert response.status_code == 403


@pytest.mark.parametrize('outcome', ['conducted', 'canceled'])
def test_hack_future_return_sign_scan_evaluate(sap_system, monkeypatch, outcome):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    old = db.query(SAPRevision).one()
    old_bytes, old_snapshot = old.printable_pdf, deepcopy(old.snapshot)
    checkpoint(sap_system, 1)
    assert client.post(base + '/return', json={'expected_version': version(client, base), 'remarks': ' '}).status_code == 422
    result = client.post(base + '/return', json={'expected_version': version(client, base), 'remarks': 'Move the activity to the afternoon to avoid morning classes.'})
    assert result.status_code == 200
    data = fixture_data()
    data['details'].update(start_time='13:00:00', end_time='16:00:00')
    data['collections']['program-flow'] = [dict(start='13:00:00', end='16:00:00', activity='Seminar')]
    data['collections']['affected-classes'] = []
    data['clearance'].update(class_interruption='none', class_interruption_remarks='Afternoon slot avoids morning classes')
    populate(sap_system, data)
    db.refresh(old)
    assert old.printable_pdf == old_bytes and old.snapshot == old_snapshot
    assert client.get(base + '/workflow').json()['completed_count'] == 0
    assert client.get('/sap/verify/' + old.verification_token).json()['approval_state'] == 'superseded'
    for slot in [1, 3, 2, 4, 5, 6, 7, 8, 9]:
        result = checkpoint(sap_system, slot)
        assert result.status_code == 200, result.text
    assert db.query(DocumentRouting).filter_by(event_id=event.id).count() == 0
    rev = db.query(SAPRevision).filter_by(revision_no=2).one()
    assert client.get('/sap/verify/' + rev.verification_token).json()['approved'] is False
    uploads = []
    def upload(data, mime, extension, user_id, org_id):
        uploads.append((data, mime, extension, org_id))
        return 'https://private.invalid/scan.pdf'
    monkeypatch.setattr('app.routers.sap.storage.upload_proposal_letter', upload)
    scan = render_proposal(data, 2)  # Simulated flattened scan; no forged sample signatures.
    response = client.post(base + '/final-signed-copy', data={'expected_version': version(client, base)}, files={'file': ('signed.pdf', scan, 'application/pdf')})
    assert response.status_code == 201, response.text
    assert len(uploads) == 1 and db.query(SAPFinalCopy).count() == 1
    verified = client.get('/sap/verify/' + rev.verification_token).json()
    assert verified['approved'] and 'storage_ref' not in verified and 'title' not in verified
    monkeypatch.setattr('app.routers.sap.institution_today', lambda: date(2026, 10, 29))
    # Fixture has no post-activity presets; reuse tested closure initialization with a spy.
    initialized = []
    monkeypatch.setattr('app.routers.sap.ensure_post_requirements', lambda db, event: initialized.append(event.id))
    response = client.post(base + '/evaluation', json={'expected_version': version(client, base), 'outcome': outcome, 'remarks': 'SDS final evaluation'})
    assert response.status_code == 200, response.text
    assert response.json()['evaluation']['outcome'] == outcome and event.status == 'completed'
    assert bool(initialized) == (outcome == 'conducted')
    assert db.query(Notification).filter_by(kind='sap_workflow').count() > 0
    login('treasurer')
    assert client.get(base + '/final-signed-copy').status_code == 403


def test_generic_routes_cannot_bypass_sap(sap_system):
    client, db, users, event, login, base = sap_system
    assert client.post(f'/events/{event.id}/submit').status_code == 409
    assert client.delete(f'/events/{event.id}').status_code == 409
    populate(sap_system)
    assert client.patch(base, json={'expected_version': version(client, base), 'details': fixture_data()['details']}).status_code == 409


def test_final_scan_requires_all_slots_and_valid_pdf(sap_system):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    login('sds_staff')
    for content, expected in [(b'not a pdf', 422), (render_proposal(fixture_data(), 1), 409)]:
        response = client.post(base + '/final-signed-copy', data={'expected_version': version(client, base)}, files={'file': ('scan.pdf', content, 'application/pdf')})
        assert response.status_code == expected, response.text


def test_pdf_overflow_is_rejected_not_truncated():
    data = fixture_data()
    data['details']['rationale'] = '\n'.join(['Long line'] * 150)
    with pytest.raises(ValueError, match='six-page'):
        render_proposal(data, 1)


def test_migration_security_contract():
    sql = (Path(__file__).parents[1] / 'supabase/migrations/20261017000100_sap_fo_020.sql').read_text(encoding='utf-8')
    assert 'ENABLE ROW LEVEL SECURITY' in sql
    assert 'FROM PUBLIC, anon, authenticated, service_role' in sql
    assert 'REVOKE UPDATE, DELETE ON public.sap_revisions' in sql
    assert 'sap_checkpoint_immutable' in sql and 'sap_final_copy_immutable' in sql


def test_partial_draft_and_projection_before_review(sap_system):
    client, db, users, event, login, base = sap_system
    response = client.patch(base, json={'expected_version': version(client, base), 'details': {'title': 'Partial'}})
    assert response.status_code == 200 and response.json()['details'] == {'title': 'Partial'}
    response = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert response.status_code == 422
    response = client.patch(base, json={'expected_version': version(client, base), 'details': fixture_data()['details']})
    assert response.status_code == 200
    assert event.event_date == date(2026, 10, 28) and event.start_time.hour == 8
    assert event.status == 'draft'


def test_submit_does_not_invalidate_unchanged_clearance(sap_system, monkeypatch):
    client, db, users, event, login, base = sap_system
    calls = []
    monkeypatch.setattr('app.services.sap.invalidate_clearance', lambda db, event: calls.append(event.id))
    populate(sap_system)
    assert calls == [event.id]  # Draft projection changes date; submission changes nothing.


def test_pre_activity_readiness_blocks_submission(sap_system, monkeypatch):
    client, db, users, event, login, base = sap_system
    def blocked(db, event):
        raise HTTPException(409, 'Required participant documents remain unverified')
    monkeypatch.setattr('app.services.sap.require_pre_activity_clearance', blocked)
    data = fixture_data()
    client.patch(base, json={'expected_version': version(client, base), 'details': data['details']})
    for key, items in data['collections'].items():
        client.put(base + '/' + key, json={'expected_version': version(client, base), 'items': items})
    login('sds_staff')
    client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': data['clearance']})
    login('treasurer')
    response = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert response.status_code == 409
    assert db.query(SAPRevision).count() == 0 and event.status == 'draft'


@pytest.mark.parametrize('role', ['treasurer', 'adviser', 'admin', 'super_admin', 'officer', 'signatory'])
def test_only_sds_may_record_or_evaluate(sap_system, role):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    step = client.get(base + '/workflow').json()['steps'][0]['id']
    current = version(client, base)
    login(role)
    assert client.post(base + f'/workflow/{step}/record', json={
        'expected_version': current, 'signer_name': 'Someone', 'signer_reference': 'person-1',
        'physical_signature_date': date.today().isoformat()}).status_code == 403
    assert client.post(base + '/evaluation', json={'expected_version': current, 'outcome': 'canceled', 'remarks': 'Cancelled'}).status_code == 403


def test_private_storage_failure_does_not_approve(sap_system, monkeypatch):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    for slot in range(1, 10):
        assert checkpoint(sap_system, slot).status_code == 200
    from app.services.storage import StorageError
    def unavailable(*args):
        raise StorageError('unavailable')
    monkeypatch.setattr('app.routers.sap.storage.upload_proposal_letter', unavailable)
    response = client.post(base + '/final-signed-copy', data={'expected_version': version(client, base)},
        files={'file': ('scan.pdf', render_proposal(fixture_data(), 1), 'application/pdf')})
    assert response.status_code == 503
    assert event.status == 'pending_institutional_review' and db.query(SAPFinalCopy).count() == 0
