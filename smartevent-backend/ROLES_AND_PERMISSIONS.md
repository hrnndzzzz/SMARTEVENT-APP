# Roles and permissions

This is the current backend policy. It supersedes the older role and registration
examples in README.md and SETUP.md.

## Ownership and hierarchy

The institution appoints a school IT administrator as **Super Admin**. Account
credentials should belong to that appointed staff member. The software cannot
select the person who holds this responsibility.

Super Admin -> Organization Admin -> Adviser / Treasurer / Officer.
SDS Staff has a separate oversight role for proposal letters. Signatories have
a separate institutional review role, not general operational access.

Each organization belongs to one department. Each Admin, Adviser, Treasurer,
and Officer account belongs to one organization and that organization's department.
Several organizations can belong to the same department. Sharing a department
does not grant access to another organization's records.

Super Admin is the only role with global operational access. SDS Staff can read
proposal letters across the school, but cannot read events, finances, inventory,
reports, user accounts, rosters, or administrative audit history.

## Operational and SDS duties

| Action | Super Admin | Organization Admin | Adviser | Treasurer | Officer | SDS Staff |
|---|---|---|---|---|---|---|
| Create departments and organizations | Yes | No | No | No | No | No |
| Create Admin, SDS and Signatory accounts | Yes | No | No | No | No | No |
| Manage unclaimed member roster | All | Own organization | No | No | No | No |
| List/manage registered member access | All | Own organization's Adviser/Treasurer/Officer accounts | No | No | No | No |
| Transfer accounts to another organization | Yes | No | No | No | No | No |
| Read operational data, reports, analytics | All | Own organization | Own organization | Own organization | Own organization | No |
| Create/update/delete budget categories | All | Own organization | No | No | No | No |
| Create event proposals | All | Own organization | Own organization | Own organization | No | No |
| Edit/submit/delete draft events | All | Own organization | Own drafts | Own drafts | No | No |
| Approve/reject events and expenses | Others' submissions at authorized operational stage | Others' organization submissions at authorized operational stage | Others' organization submissions at authorized adviser stage | No | No | No |
| Configure institutional event routing | All eligible events | Own organization | No | No | No | No |
| Record income and expenses | All | Own organization | No | Own organization | No | No |
| Edit/delete pending expenses and attach receipts | All | Own organization | No | Own pending expenses | No | No |
| Create/edit/delete inventory catalog and confirm drafts | All | Own organization | No | No | No | No |
| Record inventory movements | All | Own organization | Own organization | Own organization | No | No |
| Upload proposal letters | All | Own organization | Own organization | Own organization | No | No |
| Read proposal letters | All | Own organization | Own organization | Own organization | No | All |
| Read administrative audit history | All | Own organization | No | No | No | No |

The officer role is read-only regardless of position (President, Secretary, etc.).
A Treasurer needs the separate treasurer role to record finances. Officer
password changes and password recovery remain allowed as account self-service.
The shared write restriction runs on every protected operational router.

## Signatory duties and institutional review

The `signatory` role is provisioned only by Super Admin through
`POST /auth/register/signatory`. It has no organization/department assignment.
After mandatory password setup, an Admin/Super Admin may assign it to an event's
ordered route. See [Phase 1 implementation](PHASE_1_IMPLEMENTATION.md) for the
complete workflow, migration and frontend contract.

- Read only assigned current-round events, approval/routing history and their
  proposal letters while the event is `pending_institutional_review`.
- Approve/reject only the next assigned institutional step. All steps must approve
  in sequence before the event becomes `approved`; a rejection starts revision.
- No event editing, proposal uploads, finances, inventory, reports, roster or
  general administration. Personal account/password/inbox actions remain available.
- No institution-review bypass for Admin or Super Admin. Their event approval
  advances `pending_admin` to `pending_institutional_review`, not `approved`.
- Resubmission retains history and opens a new review round. Signatory access ends
  when the event leaves institutional review. Routes cannot change mid-review.

No role, including Super Admin, can approve or reject its own submissions.
Record ownership is stored on the record; transferring an account does not
transfer historical events, expenses, categories, or inventory.

## Account administration

1. Create the initial Super Admin with python -m scripts.create_super_admin
   or python -m scripts.seed_initial_data --create-admin. There is no public
   HTTP route that creates Super Admins.
2. Super Admin creates departments (POST /departments) and organizations
   (POST /organizations), or uses existing migration organizations.
3. Super Admin creates an organization administrator with
   POST /auth/register/admin, providing both department_id and
   organization_id. Admins cannot create other Admin, SDS or Signatory accounts.
4. Admin adds Adviser, Treasurer, and Officer roster entries with
   POST /cite-members. Its organization and department are used by default.
   Super Admin must specify both. Users register with their roster email and
   password; the role and organization come from the roster.
5. Change unclaimed roster roles/positions with PATCH /cite-members/{id}.
   Claimed roster entries are managed through their registered user account.
6. List members with GET /users. Super Admin can filter by department or
   organization; Admin sees only the member accounts it can manage.
7. Use PATCH /users/{id}/access to change a member role/position, or set
   is_suspended: true to revoke access. Suspension blocks existing tokens
   on their next request, login, and registration verification.
8. Set is_suspended: false to restore access. This does not verify an
   unverified registration or bypass required password setup.
9. Super Admin can transfer users with organization_id through the access
   endpoint; the department is derived from the destination organization.
   The existing PATCH /users/{id}/department Admin repair endpoint now
   requires both organization and department IDs.

Accounts on the member roster retain one of its three member roles.
Administrative, SDS and Signatory accounts use separate provisioning routes. Users cannot
alter their own role, scope, or suspension through administrative endpoints.
Super Admin account access cannot be changed through these endpoints; bootstrap
and recovery remain institution-controlled maintenance operations.

Administrative account changes, roster changes, and department/organization
creation write audit records in the same database transaction. Read these using
GET /audit-logs?limit=100&offset=0. There are no audit edit/delete routes.
GET /auth/permissions describes the authenticated user's role and duties.

## Database rollout

Apply migrations 001 through 003 if needed, then apply
[004_roles_and_organizations.sql](scripts/004_roles_and_organizations.sql) in the
Supabase SQL Editor as part of the historical setup. Also apply remaining
unapplied scripts 005–008, then the [Phase 1 migration](supabase/migrations/20261004005904_phase1_institutional_routing_compliance.sql)
before starting the current backend. Do not blindly repeat already-applied SQL.

Migration 004 adds organization ownership, suspension, scope indexes, and role
constraints. It creates a clearly named migration organization for each existing
department and assigns legacy department-scoped accounts/records to it. Review
these assignments before dividing a department into multiple organizations.
It changes catalog name uniqueness from school-wide to within an organization.

Records/accounts without a department remain unassigned; ordinary users cannot
access them. Super Admin can repair user and unclaimed roster assignments using
the endpoints above. Assign legacy operational rows using reviewed SQL matching
their actual organization; never infer ownership from a user's current position.
The database constraint initially leaves legacy rows unvalidated so they can be
repaired, but it checks new inserts and updates immediately.

The backend authenticates application JWTs and enforces this policy for API
requests. This migration does not replace existing Supabase RLS policies or
authorize direct client access to database tables.

## Phase 2/3 attendance and closeout permissions

| Action | Authorized role and stage |
|---|---|
| Maintain the participating roster | Scoped Admin/Super Admin; draft/rejected only. No student accounts. |
| Assign or correct parallel activities | Scoped Admin/Super Admin/Adviser; draft/rejected or completed. Requires equivalent objectives, instructions and reason. |
| Generate/print attendance | Scoped Admin/Super Admin/Adviser; approved/completed; active attending roster only. |
| Upload/verify signed attendance | Scoped Admin/Super Admin/Adviser; approved/completed. |
| Mark the activity completed | Scoped Admin/Super Admin/Adviser; approved only, actual date not before the activity or in the future. |
| Add/upload/verify post-activity student work and reports | Scoped Admin/Super Admin/Adviser; completed only. |
| Upload/verify alternative work | Scoped Admin/Super Admin/Adviser; approved/completed. |

Treasurer, Officer, SDS Staff and Signatory do not receive these student/closeout
permissions. Treasurer retains own pre-activity logistics uploads. Officer remains
read-only; Signatory reviews only the next assigned institutional step. Printing
does not change attendance or approvals. `completed` records the end of an event;
derived closeout `CLOSED` requires verified evidence and can reopen on replacement.

## Verification

Run .venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app.
Authorization tests use an isolated in-memory database and do not contact
Supabase. They verify real list/detail isolation between organizations sharing
a department, officer write denial across registered routes, account suspension,
role changes with existing tokens, user transfers, audit visibility, and self-review.
