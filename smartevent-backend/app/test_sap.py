"""Isolated SAP workflow, security, paper evidence and generic routing regression."""
from copy import deepcopy
import hashlib
from datetime import date
from io import BytesIO
from pathlib import Path
import pytest
from pypdf import PdfReader
from fastapi import HTTPException
from app.test_access_management import system
from app.config import settings
from app.models import DocumentRouting, Notification, Organization
from app.models_sap import SAPRevision, SAPFinalCopy, SAPReview
from app.schemas_sap import validate_submission
from app.services.sap_pdf import render_proposal, signature_slots


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
    monkeypatch.setattr('app.services.sap.institution_today', lambda: date(2026, 9, 27))
    monkeypatch.setattr(settings, 'sap_verification_base_url', 'https://example.org/sap/verify')
    login('treasurer')
    base = f'/events/{event.id}/sap-proposal'
    assert client.post(base).status_code == 201
    return client, db, users, event, login, base


def version(client, base):
    response = client.get(base)
    assert response.status_code == 200, response.text
    return response.json()['version']


def send(ctx, data=None, proposer='treasurer'):
    """Parts 1-3 filled and sent, which leaves the proposal with the Moderator and the Dean."""
    client, db, users, event, login, base = ctx
    data = data or fixture_data()
    login(proposer)
    result = client.patch(base, json={'expected_version': version(client, base), 'details': data['details']})
    assert result.status_code == 200, result.text
    for key, items in data['collections'].items():
        result = client.put(base + '/' + key, json={'expected_version': version(client, base), 'items': items})
        assert result.status_code == 200, result.text
    result = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert result.status_code == 200, result.text
    return result.json()


def department_approves(ctx):
    """The Moderator, when it is their turn, and then the Dean approve the sent proposal."""
    client, db, users, event, login, base = ctx
    reviewers = ['adviser', 'admin'] if event.status == 'pending_adviser' else ['admin']
    for role in reviewers:
        login(role)
        result = client.post(f'/events/{event.id}/approve', json={})
        assert result.status_code == 200, result.text


def populate(ctx, data=None, proposer='treasurer'):
    client, db, users, event, login, base = ctx
    data = data or fixture_data()
    send(ctx, data, proposer)
    department_approves(ctx)
    login('sds_staff')  # Part 4 is the SDS Office's, filled once the proposal reaches it.
    result = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': data['clearance']})
    assert result.status_code == 200, result.text
    login(proposer)
    return client.get(base).json()


def checkpoint(ctx, slot):
    client, db, users, event, login, base = ctx
    login('sds_staff')
    workflow = client.get(base + '/workflow').json()
    row = workflow['steps'][slot - 1]
    return client.post(base + f"/workflow/{row['id']}/record", json={
        'expected_version': workflow['version'], 'signer_name': users['treasurer'].full_name if slot == 1 else f'Physical signer {slot}',
        'signer_reference': f'institution-person-{slot}', 'assigned_user_id': str(users['treasurer'].id) if slot == 1 else None,
        'physical_signature_date': date.today().isoformat(), 'remarks': 'SDS checked the paper', 'recorded_on_behalf': True})


def test_official_form_and_addenda_keep_all_data():
    data = fixture_data()
    reader = PdfReader(BytesIO(render_proposal(data, 1, 'https://example.org/sap/verify/test-token')))
    assert len(reader.pages) >= 3
    text = '\n'.join(page.extract_text() for page in reader.pages)
    assert '145' in text and '2500.00' in text and 'SAS-SDS-FO-020' in text
    assert len(signature_slots(data['details'])) == 9
    assert 'https://example.org/sap/verify/test-token' in text
    assert 'SIGNED AND APPROVED BY SDS OFFICE' not in text
    assert 'Professional elective' in text and 'Professor B' in text
    assert all('/Annots' not in page for page in reader.pages)


def sign_current(ctx):
    client, db, users, event, login, base = ctx
    login('sds_staff')
    response = client.post(base + '/sds-sign', json={
        'expected_version': version(client, base),
        'signature_strokes': [[{'x': 0.1, 'y': 0.2}, {'x': 0.8, 'y': 0.7}]],
    })
    assert response.status_code == 200, response.text
    assert response.json()['state'] == 'sds_signed'
    return response


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
    login('sds_staff')
    assert client.patch(base, json={'expected_version': current, 'details': fixture_data()['details']}).status_code == 403
    login('treasurer')
    assert client.patch(base, json={'expected_version': current + 1, 'details': fixture_data()['details']}).status_code == 409


def test_organization_colleague_continues_a_draft(sap_system):
    client, db, users, event, login, base = sap_system
    data, current = fixture_data(), version(client, base)
    users['officer'].position = 'Vice President'
    users['adviser'].organization_id = db.query(Organization.id).filter_by(code='B').scalar()
    db.commit()
    login('adviser')
    assert client.patch(base, json={'expected_version': current, 'details': data['details']}).status_code == 403
    login('officer')
    response = client.patch(base, json={'expected_version': current, 'details': data['details']})
    assert response.status_code == 200, response.text
    response = client.put(base + '/budget-items', json={'expected_version': response.json()['version'], 'items': data['collections']['budget-items']})
    assert response.status_code == 200, response.text


def test_admin_edits_a_colleagues_draft_but_sends_only_their_own(sap_system):
    client, db, users, event, login, base = sap_system
    login('admin')
    response = client.patch(base, json={'expected_version': version(client, base), 'details': fixture_data()['details']})
    assert response.status_code == 200, response.text
    assert client.post(base + '/submit', json={'expected_version': version(client, base)}).status_code == 403


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
    for slot in [1, 3, 2, 4]:
        result = checkpoint(sap_system, slot)
        assert result.status_code == 200, result.text
    sign_current(sap_system)
    for slot in [5, 6, 7, 8, 9]:
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


def test_long_text_stays_in_its_cell():
    data = fixture_data()
    data['details']['rationale'] = '\n'.join(['Long line'] * 150)
    data['collections']['budget-items'] = [{'particulars': f'Budget line {i}', 'amount': '1.00'} for i in range(16)]
    pages = [page.extract_text() for page in PdfReader(BytesIO(render_proposal(data, 1))).pages]
    text = '\n'.join(pages)
    assert text.count('Long line') == 150
    assert 'See addendum' not in text
    assert 'Long line' in next(page for page in pages if 'Rationale:' in page)
    assert 'Budget line 15' in text


def test_signed_revision_correction_preserves_pdf(sap_system):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    sign_current(sap_system)
    review = db.query(SAPReview).one()
    original_pdf, original_hash = review.signed_pdf, review.signed_pdf_sha256
    login('treasurer')
    assert client.post(base + '/revise', json={'expected_version': version(client, base), 'remarks': 'Correct the venue'}).status_code == 403
    login('sds_staff')
    response = client.post(base + '/revise', json={'expected_version': version(client, base), 'remarks': 'Correct the venue'})
    assert response.status_code == 200 and response.json()['state'] == 'revision_requested'
    assert client.get(base + '/pdf?revision_no=1').content == original_pdf
    populate(sap_system)
    assert client.get(base).json()['sds_review'] is None
    db.refresh(review)
    assert review.signed_pdf == original_pdf and review.signed_pdf_sha256 == original_hash


def test_returned_pdf_keeps_no_remark_text_on_the_plain_form(sap_system):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    login('sds_staff')
    response = client.post(base + '/return', json={'expected_version': version(client, base), 'remarks': 'Revise the food budget'})
    assert response.status_code == 200
    pdf = client.get(base + '/pdf')
    text = '\n'.join(page.extract_text() for page in PdfReader(BytesIO(pdf.content)).pages)
    assert 'Revise the food budget' not in text  # the remark travels as a comment, not on the plain form
    assert 'SIGNED AND APPROVED BY SDS OFFICE' not in text
    assert 'Revise the food budget' in pdf_words(client.get(base + '/pdf?comments=true').content)


def pdf_words(content):
    """The printed text on one line: Word wraps a comment inside its narrow margin."""
    return ' '.join(' '.join(page.extract_text() for page in PdfReader(BytesIO(content)).pages).split())


def review_pending(ctx, remark='Please recheck the speaker fee'):
    """A reviewed proposal still with the SDS Office: a section remark and an overall one are saved."""
    client, db, users, event, login, base = ctx
    populate(ctx)
    login('sds_staff')
    saved = client.put(base + '/sds-review', json={'expected_version': version(client, base), 'overall_remarks': 'Overall looks fine',
                                                   'section_remarks': {'budget': remark}})
    assert saved.status_code == 200, saved.text


def test_the_pdf_comes_with_or_without_the_sds_comments(sap_system):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    plain, commented = client.get(base + '/pdf'), client.get(base + '/pdf?comments=true')
    assert plain.status_code == commented.status_code == 200
    assert 'please recheck the speaker fee' not in pdf_words(plain.content).lower()
    assert 'Please recheck the speaker fee' in pdf_words(commented.content) and 'Overall: Overall looks fine' in pdf_words(commented.content)
    assert plain.content != commented.content
    assert plain.headers['content-disposition'].endswith(f'-r1.pdf"')
    assert commented.headers['content-disposition'].endswith('-r1-comments.pdf"')
    assert client.get(base + '/pdf').content == plain.content  # the cache keeps the two versions apart


def test_a_proposal_without_remarks_prints_the_same_either_way(sap_system):
    client, db, users, event, login, base = sap_system
    populate(sap_system)
    login('sds_staff')
    same, plain = (PdfReader(BytesIO(client.get(base + '/pdf' + flag).content)) for flag in ('?comments=true', ''))  # Word stamps each render, so not byte for byte
    assert [p.extract_text() for p in same.pages] == [p.extract_text() for p in plain.pages]
    assert [p.mediabox.width for p in same.pages] == [p.mediabox.width for p in plain.pages]


def test_the_draft_preview_accepts_the_flag(sap_system):
    client, db, users, event, login, base = sap_system
    draft = client.patch(base, json={'expected_version': version(client, base), 'details': fixture_data()['details']})
    assert draft.status_code == 200, draft.text
    plain, flagged = client.get(base + '/pdf?draft=true'), client.get(base + '/pdf?draft=true&comments=true')
    assert flagged.status_code == 200 and flagged.content == plain.content
    assert 'comments' not in flagged.headers['content-disposition']


def test_a_signed_revision_serves_its_stored_copy_and_a_commented_copy(sap_system):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    sign_current(sap_system)
    review = db.query(SAPReview).one()
    stored, digest = review.signed_pdf, review.signed_pdf_sha256
    assert client.get(base + '/pdf').content == stored
    commented = client.get(base + '/pdf?comments=true')
    assert commented.status_code == 200 and commented.content != stored
    text = pdf_words(commented.content)
    assert 'Please recheck the speaker fee' in text and 'SIGNED AND APPROVED BY SDS OFFICE' in text
    assert users['sds_staff'].full_name in text and 'recheck the speaker fee' not in pdf_words(stored)
    db.refresh(review)
    assert review.signed_pdf == stored and review.signed_pdf_sha256 == digest


def store_old_copy(db, review, pages=1):
    """A signed copy as the code before ea911cd stored it: the remarks printed under the signature."""
    from reportlab.pdfgen import canvas
    buffer = BytesIO()
    page = canvas.Canvas(buffer)
    page.drawString(50, 800, 'SDS: Overall looks fine')
    page.drawString(50, 780, 'Budget: Please recheck the speaker fee')
    for _ in range(pages):
        page.showPage()
    page.save()
    review.signed_pdf = buffer.getvalue()
    review.signed_pdf_sha256 = hashlib.sha256(review.signed_pdf).hexdigest()
    db.commit()
    return review.signed_pdf


def test_a_copy_stored_with_remarks_under_the_signature_is_served_clean(sap_system):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    sign_current(sap_system)
    review = db.query(SAPReview).one()
    stored = store_old_copy(db, review)
    digest = review.signed_pdf_sha256
    served = client.get(base + '/pdf')
    assert served.status_code == 200 and served.content != stored
    text = pdf_words(served.content)
    assert 'Overall looks fine' not in text and 'recheck the speaker fee' not in text
    assert 'SIGNED AND APPROVED BY SDS OFFICE' in text and users['sds_staff'].full_name in text
    db.refresh(review)
    assert review.signed_pdf == stored and review.signed_pdf_sha256 == digest


def test_an_old_stored_copy_is_served_as_is_while_word_is_down(sap_system, monkeypatch):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    sign_current(sap_system)
    stored = store_old_copy(db, db.query(SAPReview).one())
    def down(*args, **kwargs):
        raise RuntimeError('Word is busy')
    monkeypatch.setattr('app.routers.sap.render_proposal', down)
    served = client.get(base + '/pdf')
    assert served.status_code == 200 and served.content == stored


def test_an_old_stored_copy_is_served_as_is_once_its_part_4_is_gone(sap_system):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    sign_current(sap_system)
    stored = store_old_copy(db, db.query(SAPReview).one())
    assert client.post(base + '/revise', json={'expected_version': version(client, base), 'remarks': 'Correct the venue'}).status_code == 200
    served = client.get(base + '/pdf')
    assert served.status_code == 200 and served.content == stored


def test_the_final_scan_is_checked_against_the_copy_that_was_served(sap_system, monkeypatch):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    for slot in range(1, 5):
        assert checkpoint(sap_system, slot).status_code == 200
    sign_current(sap_system)
    for slot in range(5, 10):
        assert checkpoint(sap_system, slot).status_code == 200
    review = db.query(SAPReview).one()
    store_old_copy(db, review)
    clean = client.get(base + '/pdf').content
    store_old_copy(db, review, pages=len(PdfReader(BytesIO(clean)).pages) + 1)  # one page longer than the clean render
    monkeypatch.setattr('app.routers.sap.storage.upload_proposal_letter', lambda *args: 'https://private.invalid/scan.pdf')
    login('sds_staff')
    longer = review.signed_pdf
    response = client.post(base + '/final-signed-copy', data={'expected_version': version(client, base)}, files={'file': ('scan.pdf', longer, 'application/pdf')})
    assert response.status_code == 422 and 'every page' in response.json()['detail']  # the old copy's page count is not the copy the organization was served
    response = client.post(base + '/final-signed-copy', data={'expected_version': version(client, base)}, files={'file': ('scan.pdf', clean, 'application/pdf')})
    assert response.status_code == 201, response.text


GONE = 'The commented copy of this signed revision is no longer available. Download it without comments for the signed form.'


def test_a_signed_revision_after_a_correction_request_has_no_commented_copy(sap_system):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    sign_current(sap_system)
    stored = db.query(SAPReview).one().signed_pdf
    assert client.post(base + '/revise', json={'expected_version': version(client, base), 'remarks': 'Correct the venue'}).status_code == 200
    gone = client.get(base + '/pdf?comments=true')
    assert gone.status_code == 409 and gone.json()['detail'] == GONE
    assert client.get(base + '/pdf').content == stored


def test_an_older_signed_revision_has_no_commented_copy_once_a_newer_one_exists(sap_system):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    sign_current(sap_system)
    stored = db.query(SAPReview).one().signed_pdf
    assert client.post(base + '/revise', json={'expected_version': version(client, base), 'remarks': 'Correct the venue'}).status_code == 200
    populate(sap_system)
    assert client.get(base).json()['revision_no'] == 2
    gone = client.get(base + '/pdf?revision_no=1&comments=true')
    assert gone.status_code == 409 and gone.json()['detail'] == GONE
    assert client.get(base + '/pdf?revision_no=1').content == stored


@pytest.mark.parametrize('route,body', [('/return', {'remarks': 'Revise the food budget'}), ('/sds-reject', {'remarks': 'Revise the food budget'})])
def test_a_returned_or_rejected_revision_serves_both_versions(sap_system, route, body):
    client, db, users, event, login, base = sap_system
    review_pending(sap_system)
    assert client.post(base + route, json={'expected_version': version(client, base), **body}).status_code == 200
    plain, commented = pdf_words(client.get(base + '/pdf').content), pdf_words(client.get(base + '/pdf?comments=true').content)
    assert 'Revise the food budget' not in plain and 'Revise the food budget' in commented
    assert ('REJECTED BY THE SDS OFFICE' in plain) == ('REJECTED BY THE SDS OFFICE' in commented) == (route == '/sds-reject')


@pytest.mark.parametrize('data,mime', [(b'%PDF-not-a-document', 'application/pdf'), (b'\x89PNG\r\n\x1a\ninvalid', 'image/png')])
def test_supporting_files_reject_invalid_content(data, mime):
    from app.routers.sap import _validated_attachment
    with pytest.raises(HTTPException) as caught:
        _validated_attachment(data, mime)
    assert caught.value.status_code == 422


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
    for slot in range(1, 5):
        assert checkpoint(sap_system, slot).status_code == 200
    sign_current(sap_system)
    for slot in range(5, 10):
        assert checkpoint(sap_system, slot).status_code == 200
    from app.services.storage import StorageError
    def unavailable(*args):
        raise StorageError('unavailable')
    monkeypatch.setattr('app.routers.sap.storage.upload_proposal_letter', unavailable)
    response = client.post(base + '/final-signed-copy', data={'expected_version': version(client, base)},
        files={'file': ('scan.pdf', render_proposal(fixture_data(), 1), 'application/pdf')})
    assert response.status_code == 503
    assert event.status == 'pending_institutional_review' and db.query(SAPFinalCopy).count() == 0


def test_sds_sees_an_event_once_its_proposal_is_sent(sap_system):
    # The SDS Office had no way to find a proposal: /events refused the role
    # outright, so a sent proposal never reached its queue in the app.
    ctx = sap_system
    client, db, users, event, login, base = ctx
    login('sds_staff')
    assert client.get('/events').json() == []
    assert client.get(f'/events/{event.id}').status_code == 403

    submitted = populate(ctx)
    login('sds_staff')
    assert [row['id'] for row in client.get('/events').json()] == [str(event.id)]
    assert client.get(f'/events/{event.id}').status_code == 200
    assert client.get(f'/events/{event.id}/approvals').status_code == 200

    # Taken back, it is the proposer's draft again and leaves the queue.
    login('treasurer')
    assert client.post(base + '/withdraw', json={'expected_version': submitted['version']}).status_code == 200
    login('sds_staff')
    assert client.get('/events').json() == []


def test_proposer_sends_alone_and_sds_fills_part_4_before_signing(sap_system):
    # Part 4 is the SDS Office's section. Sending used to require it while
    # only SDS could write it, so nothing could be sent from the app at all.
    client, db, users, event, login, base = sap_system
    data = fixture_data()
    login('treasurer')
    assert client.patch(base, json={'expected_version': version(client, base), 'details': data['details']}).status_code == 200
    for key, items in data['collections'].items():
        assert client.put(base + '/' + key, json={'expected_version': version(client, base), 'items': items}).status_code == 200
    sent = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert sent.status_code == 200, sent.text
    assert sent.json()['state'] == 'pending_department_review'
    department_approves(sap_system)

    login('sds_staff')
    assert [row['id'] for row in client.get('/events').json()] == [str(event.id)]
    strokes = [[{'x': 0.1, 'y': 0.2}, {'x': 0.8, 'y': 0.7}]]
    unsigned = client.post(base + '/sds-sign', json={'expected_version': version(client, base), 'signature_strokes': strokes})
    assert unsigned.status_code == 422 and unsigned.json()['detail'] == 'Complete Part 4 before signing'

    filled = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': data['clearance']})
    assert filled.status_code == 200, filled.text
    text = '\n'.join(p.extract_text() for p in PdfReader(BytesIO(client.get(base + '/pdf').content)).pages)
    assert '145:3' in text

    signed = client.post(base + '/sds-sign', json={'expected_version': version(client, base), 'signature_strokes': strokes})
    assert signed.status_code == 200, signed.text
    text = '\n'.join(p.extract_text() for p in PdfReader(BytesIO(client.get(base + '/pdf').content)).pages)
    assert '145:3' in text and 'SIGNED AND APPROVED BY SDS OFFICE' in text
    late = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': data['clearance']})
    assert late.status_code == 409


PART_4_TEXT = ('parents_consent_reason', 'attachments', 'class_interruption_remarks',
               'medical_exam_reason', 'report_of_compliance_reason', 'student_personnel_ratio')


def test_part_4_text_boxes_hold_5000_characters_and_print_them(sap_system):
    client, db, users, event, login, base = sap_system
    populate(sap_system)  # The SDS Office only sees a proposal once it is sent.
    login('sds_staff')
    for key in PART_4_TEXT:
        over = fixture_data()['clearance'] | {key: 'x' * 5001}
        response = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': over})
        assert response.status_code == 422, key
    data = fixture_data()
    data['clearance'] |= {key: ('word ' * 1000)[:4995] + f'END{i}' for i, key in enumerate(PART_4_TEXT)}
    response = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': data['clearance']})
    assert response.status_code == 200, response.text
    text = '\n'.join(page.extract_text() for page in PdfReader(BytesIO(render_proposal(data, 1))).pages)
    assert all(f'END{i}' in text for i in range(len(PART_4_TEXT)))


def test_unchanged_proposal_pdf_renders_once(sap_system, monkeypatch):
    # Word takes seconds per printout, and the app's offline sync downloads every proposal's PDF.
    client, db, users, event, login, base = sap_system
    renders = []
    monkeypatch.setattr('app.routers.sap.render_proposal', lambda *args, **kwargs: renders.append(args[1]) or b'%PDF-1.4 rendered')
    monkeypatch.setattr('app.services.sap.render_proposal', lambda *args, **kwargs: b'%PDF-1.4 submitted')
    details = fixture_data()['details']
    assert client.patch(base, json={'expected_version': version(client, base), 'details': details}).status_code == 200
    for _ in range(2):
        assert client.get(base + '/pdf?draft=true').content == b'%PDF-1.4 rendered'
    assert renders == ['DRAFT']
    # Every SAP change raises the version, so the next download shows it.
    edited = details | {'title': 'Hack the Future 2'}
    assert client.patch(base, json={'expected_version': version(client, base), 'details': edited}).status_code == 200
    assert client.get(base + '/pdf?draft=true').status_code == 200
    assert renders == ['DRAFT', 'DRAFT']
    populate(sap_system)
    for _ in range(2):
        assert client.get(base + '/pdf').content == b'%PDF-1.4 rendered'
    assert renders == ['DRAFT', 'DRAFT', 1]
