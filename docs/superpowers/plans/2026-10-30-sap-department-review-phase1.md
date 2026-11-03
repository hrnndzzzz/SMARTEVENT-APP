# SAP Department Review (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sent SAP proposal goes to the organization's Moderator, then the Dean, and reaches the SDS Office only after both approve; either may return it to the draft with remarks.

**Architecture:** One new proposal state, `pending_department_review`. The event's existing `pending_adviser` / `pending_admin` status says whose turn it is, so the existing `/events/{id}/approve` and `/reject` routes (and the app's buttons for them) serve both reviewers. A new `SAPProposal.returned_by` records who last returned a proposal, and also decides what the SDS Office may see, through one rule (`SAPProposal.seen_by_sds`) used both in queries and on loaded rows.

**Tech Stack:** FastAPI, SQLAlchemy (SQLite in tests, Supabase Postgres in production), pytest.

**Spec:** `docs/superpowers/specs/2026-10-30-sds-review-decisions-design.md`, Phase 1. It is on branch `Frontend/SDS-Addition-Setup`, not in this worktree: `git show Frontend/SDS-Addition-Setup:docs/superpowers/specs/2026-10-30-sds-review-decisions-design.md`.

## Global Constraints

- Backend only: every change is under `smartevent-backend/`.
- Work on branch `claude/sds-review-sign-error-76f6b7` (equal to `origin/feature/backend-setup`, 912dc47). Push only in Task 5, with `git push origin HEAD:refs/heads/feature/backend-setup`. Never push or merge to `develop`.
- Commits: conventional subject (`feat(sap): …`, `fix(sap): …`) and a prose body saying what a user saw and why. No `Co-Authored-By` or "Generated with" lines. Stage files by path; this plan file stays untracked until Task 5.
- Exact names: proposal state `pending_department_review`; `returned_by` values `moderator`, `dean`, `sds`; event status `pending_adviser` (Moderator's turn), `pending_admin` (Dean's turn), `pending_institutional_review` (with the SDS Office), `draft` (returned).
- The Moderator is an `adviser` of the event's organization; the Dean is an `admin` or `super_admin` of its department. Scope and self-review use the existing `assert_event_read` and `assert_not_self_review`.
- Notifications always go to the event's proposer; to SDS staff only when the proposal is, or just was, with the SDS Office. The Moderator and Dean get none (spec non-goal).
- Tests, from `smartevent-backend/`:
  `DATABASE_URL="sqlite:///:memory:" JWT_SECRET_KEY="test-secret-key-that-is-long-enough-123" "C:/Users/hrnnd/Documents/thesis/SMARTEVENT-APP - Copy/smartevent-backend/.venv/Scripts/python.exe" -m pytest -q -p no:cacheprovider <paths>`,
  written `PYTEST <paths>` below. SAP tests render real PDFs through Word, so `app/test_sap.py` takes several minutes.

## Review Focus

1. Proposals the SDS Office returned before this ships (`revision_requested`, `returned_by` NULL) must stay in its queue: the migration backfills `returned_by = 'sds'`. Pinned in Task 1 (`test_department_review_migration`).
2. A Moderator from another organization must not decide: 403. Pinned in Task 3 (`test_a_moderator_from_another_organization_is_refused`).
3. Whoever created the event must not approve it at the department step: 403. Pinned in Task 3 (`test_the_events_creator_cannot_review_it`).
4. A double tap, or a Moderator acting after the Dean's turn began: 409, nothing recorded twice. Pinned in Task 3 (`test_each_reviewer_waits_their_turn`).
5. The proposer withdraws while the Dean is deciding: the Dean's late approval is refused (409), not applied to a draft. Pinned in Task 4 (`test_withdrawing_during_department_review_tells_only_the_proposer`).

---

### Task 1: Who returned it, and the new state

**Files:**
- Modify: `smartevent-backend/app/models_sap.py:9-21` (`SAPProposal`)
- Create: `smartevent-backend/supabase/migrations/20261030000100_sap_department_review.sql`
- Modify: `smartevent-backend/app/schemas_sap.py:230` (`SAPState`), `:266-280` (`SAPProposalOut`)
- Modify: `smartevent-backend/app/services/sap.py` (`output`, `submit`)
- Modify: `smartevent-backend/app/routers/sap.py` (`revise_signed`, `return_proposal`)
- Create: `smartevent-backend/app/test_sap_department_review.py`

**Interfaces:**
- Produces: column `SAPProposal.returned_by` (`String(10)`, nullable, checked to `moderator`/`dean`/`sds`); state `pending_department_review` allowed by model and database; `returned_by` in every proposal response (`SAPProposalOut.returned_by: Literal['moderator', 'dean', 'sds'] | None`, after `return_remarks`).

- [ ] **Step 1: Write the failing tests** (new file)

```python
"""The Moderator and the Dean review a sent proposal before the SDS Office does."""
from pathlib import Path

import pytest

from app.test_access_management import system
from app.test_sap import sap_system, populate, version, sign_current


@pytest.mark.parametrize('route', ['/return', '/revise'])
def test_an_sds_return_says_so_and_sending_again_clears_it(sap_system, route):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    if route == '/revise':
        sign_current(sap_system)
    login('sds_staff')
    returned = client.post(base + route, json={'expected_version': version(client, base), 'remarks': 'Fix the budget'})
    assert returned.status_code == 200, returned.text
    assert returned.json()['returned_by'] == 'sds'
    assert returned.json()['return_remarks'] == 'Fix the budget'
    login('treasurer')
    sent = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert sent.status_code == 200, sent.text
    assert sent.json()['returned_by'] is None and sent.json()['return_remarks'] is None


def test_department_review_migration():
    sql = (Path(__file__).parents[1] / 'supabase/migrations/20261030000100_sap_department_review.sql').read_text(encoding='utf-8')
    assert "'pending_department_review'" in sql
    assert "CHECK (returned_by IN ('moderator','dean','sds'))" in sql
    assert "UPDATE public.sap_proposals SET returned_by = 'sds' WHERE state = 'revision_requested'" in sql
```

- [ ] **Step 2: Run them to see them fail**

Run: `PYTEST app/test_sap_department_review.py`
Expected: FAIL — `KeyError: 'returned_by'`, and `FileNotFoundError` for the migration.

- [ ] **Step 3: Implement**

- `SAPProposal`: add `returned_by = Column(String(10))`; add `'pending_department_review'` to the state `CheckConstraint`; add `CheckConstraint("returned_by IN ('moderator','dean','sds')")` to `__table_args__`.
- The migration, exactly:

```sql
-- A sent proposal goes to the Moderator and the Dean before the SDS Office,
-- and a returned one says who returned it.
BEGIN;
ALTER TABLE public.sap_proposals DROP CONSTRAINT sap_proposals_state_check;
ALTER TABLE public.sap_proposals ADD CONSTRAINT sap_proposals_state_check
    CHECK (state IN ('draft','pending_department_review','pending_sap_review','revision_requested','sds_signed','approved','completed','rejected'));
ALTER TABLE public.sap_proposals ADD COLUMN returned_by varchar(10)
    CONSTRAINT sap_proposals_returned_by_check CHECK (returned_by IN ('moderator','dean','sds'));
-- Until now only the SDS Office could return a proposal.
UPDATE public.sap_proposals SET returned_by = 'sds' WHERE state = 'revision_requested';
COMMIT;
```

- `SAPState`: add `'pending_department_review'`. `SAPProposalOut`: add `returned_by`.
- `output()`: include `returned_by=proposal.returned_by`. `submit()`: clear `proposal.returned_by` where it clears `return_remarks`.
- `/return` and `/revise`: set `proposal.returned_by = 'sds'` beside `return_remarks`.

- [ ] **Step 4: Run them to see them pass**

Run: `PYTEST app/test_sap_department_review.py app/test_sap_core.py`
Expected: PASS.

- [ ] **Step 5: Commit** — `feat(sap): say who returned a proposal, and add a department review state`

---

### Task 2: The SDS Office sees a proposal only once it reaches the office

**Files:**
- Modify: `smartevent-backend/app/models_sap.py` (`SDS_STATES`, `SAPProposal.seen_by_sds`)
- Modify: `smartevent-backend/app/services/event_routing.py:18-21` (`_sent_proposal_events` and its docstring)
- Modify: `smartevent-backend/app/services/sap.py:24-42` (`load`)
- Modify tests where the SDS Office acted on a draft: `app/test_sap.py` (`populate`, `test_pre_activity_readiness_blocks_submission`), `app/test_organization_hierarchy.py:326-328`, `app/test_sap_withdrawal.py` (`test_stale_withdrawal_and_review_after_withdrawal_are_rejected`), `app/test_sap_postgres.py:139` (opt-in; skipped without `SAP_TEST_POSTGRES_URL`)
- Test: `app/test_sap_department_review.py`

**Interfaces:**
- Consumes: `SAPProposal.returned_by` (Task 1).
- Produces:
  - `models_sap.SDS_STATES = ('pending_sap_review', 'sds_signed', 'approved', 'completed', 'rejected')`.
  - `SAPProposal.seen_by_sds`: a `sqlalchemy.ext.hybrid.hybrid_property` — a bool on a row, a SQL expression (with an `@seen_by_sds.expression` built from `or_`/`and_`) on the class. True when `state in SDS_STATES`, or `state == 'revision_requested' and returned_by == 'sds'`.
  - `sap.load` answers SDS staff `403 'The SDS Office sees a proposal once the Dean has approved it'` for a proposal that is not `seen_by_sds`; `_sent_proposal_events` filters on `SAPProposal.seen_by_sds`.
  - `populate(ctx, data=None, proposer='treasurer')` has the SDS Office fill Part 4 after the proposal is sent, then returns the proposal as the proposer reads it (`client.get(base).json()`), so callers get the latest `version`.

- [ ] **Step 1: Write the failing test** (add `from app.models_sap import SAPProposal`)

```python
@pytest.mark.parametrize('state,returned_by,seen', [
    ('draft', None, False),
    ('pending_department_review', None, False),
    ('revision_requested', 'moderator', False),
    ('revision_requested', 'dean', False),
    ('revision_requested', 'sds', True),
    ('pending_sap_review', None, True),
    ('sds_signed', None, True),
    ('rejected', None, True),
])
def test_the_sds_office_sees_a_proposal_once_it_reaches_the_office(sap_system, state, returned_by, seen):
    client, db, users, event, login, base = sap_system
    proposal = db.query(SAPProposal).one()
    proposal.state, proposal.returned_by = state, returned_by
    db.commit()
    login('sds_staff')
    assert (str(event.id) in [row['id'] for row in client.get('/events').json()]) is seen
    assert client.get(f'/events/{event.id}').status_code == (200 if seen else 403)
    assert client.get(base).status_code == (200 if seen else 403)
```

- [ ] **Step 2: Run it to see it fail**

Run: `PYTEST app/test_sap_department_review.py`
Expected: FAIL — `pending_department_review` and department returns are listed for the SDS Office, and a draft answers 200.

- [ ] **Step 3: Implement** `SDS_STATES`, `seen_by_sds`, the `_sent_proposal_events` filter, and the `load` check (after the proposal is fetched, before it is returned).

- [ ] **Step 4: Move the SDS Office off drafts in the existing tests**

- `populate`: proposer fills Parts 1–3 and submits (assert 200); then `login('sds_staff')` and PUT `/sds-clearance` (assert 200); then `login(proposer)` and return `client.get(base).json()`.
- `test_pre_activity_readiness_blocks_submission`: delete the three lines that log in the SDS Office, fill Part 4, and log the treasurer back in.
- `test_lead_officers_can_prepare_and_submit_owned_sap_without_sds_powers`: delete lines 326–328 (SDS login and Part 4); keep the officer's 403 on line 325.
- `test_stale_withdrawal_and_review_after_withdrawal_are_rejected`: after the SDS login, replace the loop with `assert client.get(base).status_code == 403` and a PUT `/sds-review` with `submitted['version']` answering 403; keep the `SAPReview` count of 0.
- `test_sap_postgres.py:139`: `assert future.result(timeout=8) == (403 if first == 'withdraw' else 409)`.

- [ ] **Step 5: Run the SAP tests**

Run: `PYTEST app/test_sap_department_review.py app/test_sap.py app/test_sap_withdrawal.py app/test_sap_notifications.py app/test_sap_core.py app/test_organization_hierarchy.py`
Expected: PASS.

- [ ] **Step 6: Commit** — `fix(sap): keep a proposal from the SDS Office until it reaches the office`

---

### Task 3: The Moderator, then the Dean, decide

**Files:**
- Modify: `smartevent-backend/app/services/sap.py` (`save`, new `department_review`)
- Modify: `smartevent-backend/app/routers/events.py` (`_get_event_or_404`, `approve_event`, `reject_event`)
- Modify: `smartevent-backend/app/test_sap_notifications.py:12-21` (two new rows)
- Test: `app/test_sap_department_review.py`

**Interfaces:**
- Consumes: `returned_by` (Task 1); `seen_by_sds` via `sap.load` (Task 2).
- Produces:
  - `sap.save(db, event, proposal, user, action, *, notify=False, details=None, notify_sds=True) -> dict`; `notify_sds=False` notifies the proposer only.
  - `sap.department_review(db, event, proposal, user, decision, remarks) -> dict`, `decision` in `{'approved', 'returned'}`. The caller holds the event lock and has run `assert_event_read` and `assert_not_self_review`. In order:
    - state not `pending_department_review` → `409 'This proposal is not waiting on department review'`;
    - `adviser` acts only while the event is `pending_adviser`, else `409 'The Moderator has already approved this proposal'`; `admin`/`super_admin` returns at either stage but approves only at `pending_admin`, else `409 'The Moderator approves a proposal before the Dean'`; any other role → 403;
    - `returned`: blank or missing remarks → `422 'Say what needs to change'`; else state `revision_requested`, `return_remarks = remarks`, `returned_by` `moderator` (adviser) or `dean`, `clearance = None`, event `draft`; `record_decision(db, 'event', event.id, 'returned', user, remarks)`; `save(…, 'sap_department_returned', notify=True, notify_sds=False, details={'revision', 'remarks', 'returned_by'})`;
    - Moderator approves: event `pending_admin`; `record_decision(…, 'approved', …)`; `save(…, 'sap_moderator_approved')`, audited, no notification;
    - Dean approves: state `pending_sap_review`, event `pending_institutional_review`; `record_decision(…, 'approved', …)`; `save(…, 'sap_dean_approved', notify=True)`.
  - `save`'s notification table gains `'sap_dean_approved': ('SAP proposal sent to the SDS Office', 'The Dean approved {title}. It is now with the SDS Office.')` and `'sap_department_returned': ('SAP proposal returned', '{title} was returned for changes.')`.
  - `_get_event_or_404(db, event_id, *, lock=False, allow_sap=False)`: `allow_sap=True` skips `assert_generic_workflow`. `approve_event` and `reject_event` lock with `allow_sap=True`; right after `assert_not_self_review`, an event with a `SAPProposal` goes to `department_review` (`'approved'` / `'returned'`, `payload.remarks`), then `db.refresh(event)` and the event is returned. Import `app.services.sap` inside the function, as `_get_event_or_404` already does; `SAPProposal` from `app.models_sap` at the top.

- [ ] **Step 1: Write the failing tests** (imports gain `from app.models import Approval, Notification, Organization` and `fixture_data`)

```python
def send(ctx, proposer='treasurer'):
    """Parts 1-3 filled and sent; populate stops here."""
    client, db, users, event, login, base = ctx
    data = fixture_data()
    login(proposer)
    assert client.patch(base, json={'expected_version': version(client, base), 'details': data['details']}).status_code == 200
    for key, items in data['collections'].items():
        assert client.put(base + '/' + key, json={'expected_version': version(client, base), 'items': items}).status_code == 200
    sent = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert sent.status_code == 200, sent.text
    # Until Task 4 sends it to the department, put it there by hand.
    db.query(SAPProposal).one().state, event.status = 'pending_department_review', 'pending_adviser'
    db.commit()
    return sent.json()


def decide(ctx, role, verdict, remarks=None):
    client, db, users, event, login, base = ctx
    login(role)
    return client.post(f'/events/{event.id}/{verdict}', json={} if remarks is None else {'remarks': remarks})


def test_moderator_then_dean_send_it_to_the_sds_office(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    first = decide(sap_system, 'adviser', 'approve', 'Looks fine')
    assert first.status_code == 200, first.text
    assert first.json()['status'] == 'pending_admin'
    assert db.query(SAPProposal).one().state == 'pending_department_review'
    second = decide(sap_system, 'admin', 'approve')
    assert second.status_code == 200, second.text
    assert second.json()['status'] == 'pending_institutional_review'
    assert db.query(SAPProposal).one().state == 'pending_sap_review'
    assert [(row.decision, row.reviewer_id) for row in db.query(Approval).order_by(Approval.step_order)] == [
        ('approved', users['adviser'].id), ('approved', users['admin'].id)]
    told = db.query(Notification).filter_by(title='SAP proposal sent to the SDS Office').all()
    assert {row.user_id for row in told} == {users['treasurer'].id, users['sds_staff'].id}
    login('sds_staff')
    assert client.get(base).status_code == 200


def test_each_reviewer_waits_their_turn(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    assert decide(sap_system, 'admin', 'approve').status_code == 409
    assert decide(sap_system, 'adviser', 'approve').status_code == 200
    assert decide(sap_system, 'adviser', 'approve').status_code == 409
    assert decide(sap_system, 'adviser', 'reject', 'Too late').status_code == 409
    assert db.query(Approval).count() == 1


@pytest.mark.parametrize('reviewer,after_moderator', [('adviser', False), ('admin', False), ('admin', True)])
def test_a_return_goes_back_to_the_draft_naming_who_sent_it(sap_system, reviewer, after_moderator):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    if after_moderator:
        assert decide(sap_system, 'adviser', 'approve').status_code == 200
    response = decide(sap_system, reviewer, 'reject', 'Move it to the afternoon')
    assert response.status_code == 200, response.text
    assert response.json()['status'] == 'draft'
    login('treasurer')
    proposal = client.get(base).json()
    assert proposal['state'] == 'revision_requested'
    assert proposal['return_remarks'] == 'Move it to the afternoon'
    assert proposal['returned_by'] == ('moderator' if reviewer == 'adviser' else 'dean')
    assert proposal['clearance'] is None
    told = db.query(Notification).filter_by(title='SAP proposal returned').all()
    assert [row.user_id for row in told] == [users['treasurer'].id]
    assert db.query(Approval).order_by(Approval.step_order.desc()).first().decision == 'returned'


@pytest.mark.parametrize('remarks', [None, '   '])
def test_a_return_needs_remarks(sap_system, remarks):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    assert decide(sap_system, 'adviser', 'reject', remarks).status_code == 422
    assert db.query(SAPProposal).one().state == 'pending_department_review'


@pytest.mark.parametrize('role', ['treasurer', 'officer', 'signatory', 'sds_staff'])
def test_only_the_moderator_or_dean_decide(sap_system, role):
    send(sap_system)
    for verdict in ('approve', 'reject'):
        assert decide(sap_system, role, verdict, 'No').status_code == 403


def test_a_moderator_from_another_organization_is_refused(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    users['adviser'].organization_id = db.query(Organization.id).filter_by(code='B').scalar()
    db.commit()
    assert decide(sap_system, 'adviser', 'approve').status_code == 403


def test_the_events_creator_cannot_review_it(sap_system):
    client, db, users, event, login, base = sap_system
    event.proposed_by = users['adviser'].id
    db.commit()
    send(sap_system)  # a colleague, the treasurer, sends it
    assert decide(sap_system, 'adviser', 'approve').status_code == 403


def test_a_proposal_past_department_review_is_refused_there(sap_system):
    populate(sap_system)
    assert decide(sap_system, 'adviser', 'approve').status_code == 409
```

And in `test_sap_notifications.py`'s parametrize list:

```python
    ('sap_dean_approved', 'pending_sap_review', 'now with the SDS Office'),
    ('sap_department_returned', 'revision_requested', 'returned for changes'),
```

- [ ] **Step 2: Run them to see them fail**

Run: `PYTEST app/test_sap_department_review.py app/test_sap_notifications.py`
Expected: FAIL — approve and reject answer `409 This event uses SAP`; the two notification rows fall back to "updated".

- [ ] **Step 3: Implement** `notify_sds`, `department_review`, the two texts, `allow_sap`, and the SAP branch in both routes.

- [ ] **Step 4: Run them to see them pass, with the generic approval tests**

Run: `PYTEST app/test_sap_department_review.py app/test_sap_notifications.py app/test_event_approval_workflow.py app/test_organization_hierarchy.py`
Expected: PASS.

- [ ] **Step 5: Commit** — `feat(sap): let the Moderator and the Dean approve or return a sent proposal`

---

### Task 4: Sending a proposal goes to the department first

**Files:**
- Modify: `smartevent-backend/app/services/sap.py` (`submit`, `withdraw`, `sap_submitted` text)
- Modify: `app/test_sap.py` (new `send`, `department_approves`; `populate`; `test_proposer_sends_alone_and_sds_fills_part_4_before_signing`)
- Modify: `app/test_sap_department_review.py` (drop its own `send`; import `send`, `department_approves` from `app.test_sap`)
- Modify: `app/test_sap_notifications.py` (`sap_submitted` row; `test_failed_email_retry_keeps_workflow_and_does_not_resend_sent`)
- Modify: `app/test_sap_withdrawal.py:39`, `app/test_organization_hierarchy.py:332`
- Modify: `smartevent-backend/docs/sap-fo-020-frontend-contract.md` ("State and concurrency", endpoint table)

**Interfaces:**
- Consumes: `/events/{id}/approve|reject` for proposals (Task 3); `save(…, notify_sds=…)` (Task 3).
- Produces:
  - `submit()` leaves the proposal `pending_department_review` and the event `pending_admin` when the sender or the event's creator is an `adviser` (a Moderator doesn't approve their own), else `pending_adviser`. It notifies the proposer only, `'sap_submitted': ('SAP proposal submitted', 'Sent for department review: {title}.')`.
  - `withdraw()` also accepts `pending_department_review`; any other state → `409 'Only a proposal still waiting on review can be withdrawn'`. It notifies SDS staff only when the proposal was `pending_sap_review`.
  - In `app/test_sap.py`: `send(ctx, data=None, proposer='treasurer') -> dict` (Parts 1–3 and submit, returning the submit response; no state forcing); `department_approves(ctx) -> None` (the adviser approves if the event is `pending_adviser`, then the admin approves; each asserts 200); `populate` = `send` + `department_approves` + SDS Part 4 + the proposer's `GET base`.

- [ ] **Step 1: Write the failing tests** (in `test_sap_department_review.py`)

```python
def test_sending_goes_to_the_moderator_first(sap_system):
    sent = send(sap_system)
    client, db, users, event, login, base = sap_system
    assert sent['state'] == 'pending_department_review' and event.status == 'pending_adviser'
    told = db.query(Notification).filter_by(kind='sap_workflow').all()
    assert [row.user_id for row in told] == [users['treasurer'].id]
    assert 'department review' in told[0].body
    login('sds_staff')
    assert client.get('/events').json() == []


@pytest.mark.parametrize('sender,creator', [('adviser', 'treasurer'), ('treasurer', 'adviser')])
def test_an_advisers_proposal_starts_with_the_dean(sap_system, sender, creator):
    client, db, users, event, login, base = sap_system
    event.proposed_by = users[creator].id
    db.commit()
    send(sap_system, proposer=sender)
    assert event.status == 'pending_admin'


@pytest.mark.parametrize('after_moderator', [False, True])
def test_withdrawing_during_department_review_tells_only_the_proposer(sap_system, after_moderator):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    if after_moderator:
        assert decide(sap_system, 'adviser', 'approve').status_code == 200
    login('treasurer')
    response = client.post(base + '/withdraw', json={'expected_version': version(client, base)})
    assert response.status_code == 200, response.text
    assert response.json()['state'] == 'draft' and event.status == 'draft'
    told = db.query(Notification).filter_by(title='SAP proposal withdrawn').all()
    assert [row.user_id for row in told] == [users['treasurer'].id]
    assert decide(sap_system, 'admin', 'approve').status_code == 409
```

Move `send` into `app/test_sap.py` without the two forcing lines, and import it here.

- [ ] **Step 2: Run them to see them fail**

Run: `PYTEST app/test_sap_department_review.py`
Expected: FAIL — submit still answers `pending_sap_review`, and Task 3's tests now fail too, since `send` no longer forces the state.

- [ ] **Step 3: Implement** `submit` and `withdraw` and the new `sap_submitted` text.

- [ ] **Step 4: Route the existing tests through the department**

- `populate`: `send`, `department_approves`, SDS Part 4, proposer's `GET base`.
- `test_proposer_sends_alone_and_sds_fills_part_4_before_signing`: expect `sent.json()['state'] == 'pending_department_review'`, then call `department_approves(sap_system)` before the SDS login.
- `test_sap_notifications.py`: the `sap_submitted` row becomes `('sap_submitted', 'pending_department_review', 'department review')`; `test_failed_email_retry_…` picks `filter_by(user_id=users['treasurer'].id, title='SAP proposal submitted').one()`.
- `test_sap_withdrawal.py:39`: `== 5` (sent: proposer; Dean's approval and withdrawal: proposer and SDS).
- `test_organization_hierarchy.py:332`: `== "pending_department_review"`.
- Contract doc: the state line becomes `draft -> pending_department_review -> pending_sap_review -> approved -> completed`; add a paragraph on the Moderator (`pending_adviser`) and Dean (`pending_admin`) steps through `POST /events/{event_id}/approve` and `/reject` with `{remarks}` (an adviser's proposal starts with the Dean; a return needs remarks and sets `returned_by`); the event projection names those two statuses; the `/sds-clearance` row reads "SDS fills Part 4 while `pending_sap_review`; 409 once signed"; the `/return` row adds "sets `returned_by: sds`"; note that the SDS Office sees a proposal only from the Dean's approval on, or after returning it itself.

- [ ] **Step 5: Run every SAP test file**

Run: `PYTEST app/test_sap_department_review.py app/test_sap.py app/test_sap_withdrawal.py app/test_sap_notifications.py app/test_sap_core.py app/test_sap_docx.py app/test_organization_hierarchy.py app/test_event_approval_workflow.py`
Expected: PASS.

- [ ] **Step 6: Commit** — `feat(sap): send a proposal to the Moderator and the Dean before the SDS Office`

---

### Task 5: Full suite, then push

- [ ] **Step 1: Run everything**

Run: `PYTEST app`
Expected: no failures (before Phase 1: 576 passed, 3 skipped).

- [ ] **Step 2: Check what will be pushed**

Run: `git log --oneline origin/feature/backend-setup..HEAD` and `git status --short`
Expected: the four Phase 1 commits; only this plan file untracked.

- [ ] **Step 3: Push the backend**

Run: `git push origin HEAD:refs/heads/feature/backend-setup`, then `git ls-remote --heads origin feature/backend-setup`
Expected: the remote head is the last Phase 1 commit.

- [ ] **Step 4: File this plan beside the spec**

`git switch Frontend/SDS-Addition-Setup`, commit `docs/superpowers/plans/2026-10-30-sap-department-review-phase1.md` (`docs: plan Phase 1, department review`), `git push origin Frontend/SDS-Addition-Setup`, `git switch claude/sds-review-sign-error-76f6b7`.
