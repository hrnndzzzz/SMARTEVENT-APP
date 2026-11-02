# SAP SDS Decisions (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The SDS Office can approve (sign), return, or reject a proposal with remarks; every outcome prints its remarks; a rejected proposal is final; paper slots 5–9 follow the SDS signature.

**Architecture:** Decisions share one remarks body (`DecisionWrite`: overall `remarks` plus optional `section_remarks`) and one helper that records them on the revision's `SAPReview` row, keeping saved section remarks unless new ones are sent. Rejection is a new route beside `/return`, ending in the `rejected` state the database already allows. The printout's existing "signed" stamp gains a "rejected" variant.

**Tech Stack:** FastAPI, SQLAlchemy (SQLite in tests), pytest, Word-rendered PDFs (pypdf to read them back).

**Spec:** `docs/superpowers/specs/2026-10-30-sds-review-decisions-design.md`, Phase 2 (on branch `Frontend/SDS-Addition-Setup`: `git show Frontend/SDS-Addition-Setup:docs/superpowers/specs/2026-10-30-sds-review-decisions-design.md`). Builds on Phase 1 (department review), already on this branch.

## Global Constraints

- Backend only: every change is under `smartevent-backend/`.
- Work on branch `claude/sds-review-sign-error-76f6b7`. The controller pushes it to `SDS-Workflow-setup` after Task 7; never push or merge to `develop`.
- Commits: conventional subject and a prose body saying what a user saw and why. No `Co-Authored-By` or "Generated with" lines. Stage files by path; plan files stay untracked.
- `/return` must keep accepting today's body `{expected_version, remarks}`: the app on `develop` sends exactly that.
- Exact names: state `rejected`, event status `rejected`; route `POST /sds-reject`; notification action `sap_rejected`; printout mark text `REJECTED BY THE SDS OFFICE`; remark sections `activity_details`, `budget`, `support_requests`, `additional_information`, `clearance`, `other`.
- Tests, from `smartevent-backend/`: `DATABASE_URL="sqlite:///:memory:" JWT_SECRET_KEY="test-secret-key-that-is-long-enough-123" "C:/Users/hrnnd/Documents/thesis/SMARTEVENT-APP - Copy/smartevent-backend/.venv/Scripts/python.exe" -m pytest -q -p no:cacheprovider <paths>` (written `PYTEST <paths>`). Word renders the PDFs: slow, and now and then fails with "Could not convert the SAP form to PDF" — rerun before suspecting code.
- New tests go in `smartevent-backend/app/test_sap_sds_decisions.py` (imports from `app.test_sap`: `sap_system`, `populate`, `version`, `checkpoint`, `sign_current`, `fixture_data`, `send`, `department_approves`; and `system` from `app.test_access_management`).

## Review Focus

1. A rejected proposal accepts no change from anyone — proposer, SDS Office, Moderator, Dean, paper slots. Pinned in Task 2 (`test_a_rejected_proposal_is_final`).
2. Section remarks the SDS Office saved survive a return or rejection that sends only overall remarks. Pinned in Tasks 1 and 2.
3. A colleague who sent the proposal, not the event's creator, still hears the decision. Pinned in Task 4.
4. Slots 5–9 cannot be recorded before the SDS signature, even from a stale workflow screen. Pinned in Task 3.
5. A Moderator or Dean deciding from an old screen after the proposal changed is refused. Pinned in Task 5.

---

### Task 1: Remarks travel with a return, and print

**Files:**
- Modify: `smartevent-backend/app/schemas_sap.py` (one section-remarks check shared by `SDSReviewWrite`, `ReviewNotesWrite` and the new `DecisionWrite`)
- Modify: `smartevent-backend/app/routers/sap.py` (`return_proposal`; new helper `_record_remarks`)
- Create: `smartevent-backend/app/test_sap_sds_decisions.py`

**Interfaces:**
- Produces: `DecisionWrite(Version)` with `remarks: str = Field(min_length=1, max_length=3000)` and `section_remarks: dict[str, str] | None = None` (validated like the others when given). `/return` takes `DecisionWrite`; `/revise` keeps `ReturnWrite`. `_record_remarks(db, rev, payload) -> SAPReview` in `routers/sap.py`: creates or updates the revision's `SAPReview`, sets `overall_remarks = payload.remarks`, and replaces `section_remarks` only when `payload.section_remarks is not None`.

- [ ] **Step 1: Write the failing test**

```python
"""The SDS Office's three decisions, their remarks, and what follows."""
from io import BytesIO

import pytest
from pypdf import PdfReader

from app.models import Notification
from app.models_sap import SAPProposal, SAPRevision
from app.test_access_management import system
from app.test_sap import sap_system, populate, version, checkpoint, sign_current, fixture_data, send, department_approves


def pdf_text(content):
    return '\n'.join(page.extract_text() for page in PdfReader(BytesIO(content)).pages)


@pytest.mark.parametrize('sent,kept', [(None, {'budget': 'Meals over the allowance'}),
                                       ({'other': 'Attach the venue letter'}, {'other': 'Attach the venue letter'})])
def test_a_return_keeps_section_remarks_and_prints_them(sap_system, sent, kept):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.put(base + '/sds-review', json={'expected_version': version(client, base), 'overall_remarks': 'Draft note',
                                                  'section_remarks': {'budget': 'Meals over the allowance'}}).status_code == 200
    body = {'expected_version': version(client, base), 'remarks': 'Fix the budget'}
    if sent is not None:
        body['section_remarks'] = sent
    returned = client.post(base + '/return', json=body)
    assert returned.status_code == 200, returned.text
    assert returned.json()['sds_review']['overall_remarks'] == 'Fix the budget'
    assert returned.json()['sds_review']['section_remarks'] == kept
    text = pdf_text(client.get(base + '/pdf').content)
    assert 'SDS: Fix the budget' in text
```

- [ ] **Step 2:** `PYTEST app/test_sap_sds_decisions.py` — expect the `sent` case to FAIL with 422 (`section_remarks` is an unknown field today); the `None` case already passes and must keep passing.
- [ ] **Step 3:** Implement `DecisionWrite`, the shared check, `_record_remarks`, and use them in `/return` (it still sets `return_remarks`, `returned_by = 'sds'`, clears `clearance`, and moves the event to `draft`).
- [ ] **Step 4:** `PYTEST app/test_sap_sds_decisions.py app/test_sap.py` — PASS (the old `{'remarks': ' '}` → 422 check in `test_hack_future_return_sign_scan_evaluate` must still hold).
- [ ] **Step 5: Commit** — `feat(sap): keep the SDS Office's section remarks when it returns a proposal`

---

### Task 2: The SDS Office can reject

**Files:**
- Modify: `smartevent-backend/app/routers/sap.py` (new `POST /sds-reject`; `/pdf` passes the rejected mark)
- Modify: `smartevent-backend/app/services/sap.py` (`save`'s notification table)
- Modify: `smartevent-backend/app/services/sap_pdf.py` (`render_proposal`, `_stamp`, `_watermark`, `_footer`)
- Test: `app/test_sap_sds_decisions.py`

**Interfaces:**
- Consumes: `DecisionWrite`, `_record_remarks` (Task 1).
- Produces:
  - `POST /sds-reject` (SDS only, `sap.load(..., write=True, sds=True)`, `check_version`): only from `pending_sap_review`, else `409 'Only a pending revision can be rejected'`. Records the remarks with `_record_remarks`, sets the proposal `rejected` and the event `rejected`, and `save(…, 'sap_rejected', notify=True, details={'revision', 'remarks'})`. It leaves `return_remarks` and `returned_by` alone: a rejection is not a return.
  - `save`'s table: `'sap_rejected': ('SAP proposal rejected', 'The SDS Office rejected {title}.')`.
  - `render_proposal(..., signed=False, rejected=False)`; `_stamp(..., rejected)` draws `_watermark(canvas, 'REJECTED BY THE SDS OFFICE')` instead of the signed text, and the footer says `' | Rejected by SDS'`. `/pdf` passes `rejected=True` only for the current revision of a rejected proposal.

- [ ] **Step 1: Write the failing tests**

```python
def test_the_sds_office_rejects_with_remarks_and_the_form_says_so(sap_system):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    response = client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': 'Not an organizational activity'})
    assert response.status_code == 200, response.text
    assert response.json()['state'] == 'rejected' and event.status == 'rejected'
    assert response.json()['sds_review']['overall_remarks'] == 'Not an organizational activity'
    assert response.json()['returned_by'] is None
    text = pdf_text(client.get(base + '/pdf').content)
    assert 'REJECTED BY THE SDS OFFICE' in text and 'SDS: Not an organizational activity' in text
    token = db.query(SAPRevision).one().verification_token
    assert client.get('/sap/verify/' + token).json()['approval_state'] == 'rejected'
    told = db.query(Notification).filter_by(title='SAP proposal rejected').all()
    assert users['treasurer'].id in {row.user_id for row in told}


@pytest.mark.parametrize('remarks', ['', '   '])
def test_a_rejection_needs_remarks(sap_system, remarks):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': remarks}).status_code == 422


STROKES = [[{'x': 0.1, 'y': 0.2}, {'x': 0.8, 'y': 0.7}]]
LATE_WRITES = [
    ('treasurer', 'patch', '', {'details': {'title': 'Changed'}}),
    ('treasurer', 'post', '/submit', {}),
    ('treasurer', 'post', '/withdraw', {}),
    ('sds_staff', 'put', '/sds-review', {'overall_remarks': 'Late'}),
    ('sds_staff', 'post', '/sds-sign', {'signature_strokes': STROKES}),
    ('sds_staff', 'put', '/sds-clearance', {'clearance': fixture_data()['clearance']}),
    ('sds_staff', 'post', '/return', {'remarks': 'Again'}),
    ('sds_staff', 'post', '/sds-reject', {'remarks': 'Again'}),
    ('sds_staff', 'post', '/revise', {'remarks': 'Again'}),
]


@pytest.mark.parametrize('role,method,path,body', LATE_WRITES)
def test_a_rejected_proposal_is_final(sap_system, role, method, path, body):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': 'No'}).status_code == 200
    login(role)
    response = client.request(method.upper(), base + path, json={'expected_version': version(client, base), **body})
    assert response.status_code == 409, response.text
    assert checkpoint(sap_system, 1).status_code == 409
    login('adviser')
    assert client.post(f'/events/{event.id}/approve', json={}).status_code == 409
    assert db.query(SAPProposal).one().state == 'rejected'
```

- [ ] **Step 2:** `PYTEST app/test_sap_sds_decisions.py` — expect FAIL: `/sds-reject` is 404/405.
- [ ] **Step 3:** Implement the route, the notification text, and the rejected mark.
- [ ] **Step 4:** `PYTEST app/test_sap_sds_decisions.py app/test_sap_docx.py app/test_sap_notifications.py` — PASS.
- [ ] **Step 5: Commit** — `feat(sap): let the SDS Office reject a proposal, and mark the printed form`

---

### Task 3: Paper slots 5–9 follow the SDS signature

**Files:**
- Modify: `smartevent-backend/app/routers/sap.py` (`record`), `smartevent-backend/app/services/sap.py` (`workflow`'s `actionable`)
- Modify: `app/test_sap.py` (`test_hack_future_return_sign_scan_evaluate`, `test_private_storage_failure_does_not_approve`: record slots 1–4, then `sign_current`, then 5–9)
- Test: `app/test_sap_sds_decisions.py`

**Interfaces:**
- Produces: `record` answers `409 'Slots 5 to 9 are signed after the SDS Office signs'` for a slot of 5 or more unless the proposal is `sds_signed`; `actionable` is false for those slots until then. Slots 1–4 unchanged.

- [ ] **Step 1: Write the failing test**

```python
def test_slots_five_to_nine_wait_for_the_sds_signature(sap_system):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    for slot in (1, 3, 2, 4):
        assert checkpoint(sap_system, slot).status_code == 200
    assert client.get(base + '/workflow').json()['steps'][4]['actionable'] is False
    assert checkpoint(sap_system, 5).status_code == 409
    sign_current(sap_system)
    assert client.get(base + '/workflow').json()['steps'][4]['actionable'] is True
    assert checkpoint(sap_system, 5).status_code == 200
```

- [ ] **Step 2:** `PYTEST app/test_sap_sds_decisions.py` — expect FAIL (slot 5 actionable and recorded before signing).
- [ ] **Step 3:** Implement; reorder the two named tests in `app/test_sap.py`.
- [ ] **Step 4:** `PYTEST app/test_sap_sds_decisions.py app/test_sap.py` — PASS.
- [ ] **Step 5: Commit** — `fix(sap): record paper slots 5 to 9 only after the SDS Office signs`

---

### Task 4: Notices reach whoever sent the proposal

**Files:**
- Modify: `smartevent-backend/app/services/sap.py` (`save`'s recipients)
- Modify: `app/test_sap_notifications.py` (each row says whether SDS staff hear it, and passes that as `notify_sds`)
- Test: `app/test_sap_sds_decisions.py`

**Interfaces:**
- Produces: once a proposal has a revision, `save(…, notify=True)` also notifies that revision's `submitted_by` (a set: no duplicate when the sender created the event).

- [ ] **Step 1: Write the failing test**

```python
def test_a_colleague_who_sent_it_hears_the_decision(sap_system):
    client, db, users, event, login, base = sap_system
    send(sap_system, proposer='adviser')  # the treasurer created the event
    department_approves(sap_system)
    login('sds_staff')
    assert client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': 'No'}).status_code == 200
    told = {row.user_id for row in db.query(Notification).filter_by(title='SAP proposal rejected')}
    assert {users['treasurer'].id, users['adviser'].id} <= told
```

In `test_sap_notifications.py`, add a `sds_hears` value to every parametrize row (`False` for `sap_submitted` and `sap_department_returned`, `True` otherwise, and a new `('sap_rejected', 'rejected', 'rejected', True)` row), pass `notify_sds=sds_hears`, and assert the recipients accordingly.

- [ ] **Step 2:** `PYTEST app/test_sap_sds_decisions.py app/test_sap_notifications.py` — expect FAIL: the adviser who sent it is not told.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `PYTEST app/test_sap_sds_decisions.py app/test_sap_notifications.py app/test_sap_withdrawal.py app/test_sap_department_review.py` — PASS.
- [ ] **Step 5: Commit** — `fix(sap): tell whoever sent a proposal what became of it`

---

### Task 5: A stale screen cannot decide

**Files:**
- Modify: `smartevent-backend/app/schemas.py` (`ApprovalDecision`), `smartevent-backend/app/routers/events.py` (pass it on), `smartevent-backend/app/services/sap.py` (`department_review`)
- Test: `app/test_sap_sds_decisions.py`

**Interfaces:**
- Produces: `ApprovalDecision.expected_version: int | None = Field(default=None, ge=1)`. `department_review(db, event, proposal, user, decision, remarks, expected_version=None)` runs `check_version(proposal, expected_version)` when it is given, before any other check after the decision-word check. Generic events ignore the field.

- [ ] **Step 1: Write the failing test**

```python
def test_a_stale_department_screen_is_refused(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    current = version(client, base)
    login('adviser')
    stale = client.post(f'/events/{event.id}/approve', json={'expected_version': current - 1})
    assert stale.status_code == 409 and stale.json()['detail'] == 'Proposal changed; reload before retrying'
    assert client.post(f'/events/{event.id}/approve', json={'expected_version': current}).status_code == 200
```

- [ ] **Step 2:** `PYTEST app/test_sap_sds_decisions.py` — expect FAIL (422: unknown field).
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `PYTEST app/test_sap_sds_decisions.py app/test_sap_department_review.py app/test_event_approval_workflow.py` — PASS.
- [ ] **Step 5: Commit** — `feat(sap): refuse a department decision made on an outdated proposal`

---

### Task 6: Part 4 only while the SDS Office has it, and the docs

**Files:**
- Modify: `smartevent-backend/app/routers/sap.py` (`clearance`: only `pending_sap_review`, else `409 'Part 4 is filled in while the SDS Office reviews the proposal'`)
- Modify: `smartevent-backend/docs/sap-fo-020-frontend-contract.md`, `smartevent-backend/docs/SAP_FRONTEND_IMPLEMENTATION_HANDOFF.md`
- Test: `app/test_sap_sds_decisions.py`

- [ ] **Step 1: Write the failing test**

```python
def test_part_4_waits_while_the_proposal_is_back_with_the_organization(sap_system):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.post(base + '/return', json={'expected_version': version(client, base), 'remarks': 'Fix it'}).status_code == 200
    late = client.put(base + '/sds-clearance', json={'expected_version': version(client, base), 'clearance': fixture_data()['clearance']})
    assert late.status_code == 409 and late.json()['detail'] == 'Part 4 is filled in while the SDS Office reviews the proposal'
```

- [ ] **Step 2:** `PYTEST app/test_sap_sds_decisions.py` — expect FAIL (200).
- [ ] **Step 3:** Implement. Update both docs for everything in Phase 2: the `rejected` end state and `/sds-reject` row; `/return`'s optional `section_remarks` and that saved section remarks are kept; remarks on every printed outcome and the rejected mark; slots 5–9 after the signature; notices reaching the sender; `expected_version` on approve/reject for proposals; Part 4's window. The handoff doc's "Updated:" line becomes 31 October 2026.
- [ ] **Step 4:** `PYTEST app/test_sap_sds_decisions.py app/test_sap.py` — PASS (the existing signed-revision `late` check still answers 409).
- [ ] **Step 5: Commit** — `fix(sap): keep Part 4 to the SDS Office's review, and document Phase 2`

---

### Task 7: Full suite (controller)

- [ ] `PYTEST app` — no failures; then the controller pushes to `SDS-Workflow-setup`.
