# Roles and permissions

This is the current backend policy. It supersedes the older role and registration
examples in README.md and SETUP.md.

## Ownership and hierarchy

The institution appoints a school IT administrator as **Super Admin**. Account
credentials should belong to that appointed staff member. The software cannot
select the person who holds this responsibility.

Organization hierarchy: Dean (Admin) -> Adviser / Moderator (Adviser) -> President -> other officers.
Super Admin is the platform administrator. Treasurer is a financial responsibility,
not an additional supervisory rank. Adviser and Moderator have identical permissions.
SDS Staff has a separate oversight role for proposal letters.

Each organization belongs to one department. Each Admin, Adviser, Treasurer,
and Officer account belongs to one organization and that organization's department.
Admins manage every organization in their assigned department; their stored
organization remains the default for creating records. Adviser, Treasurer and
Officer access remains limited to their own organization. Selected organizations
must belong to the Admin's department. Missing assignments fail closed.

Super Admin is the only role with global operational access. SDS Staff can read
proposal letters across the school, but cannot read events, finances, inventory,
reports, user accounts, rosters, or administrative audit history.

## Duties and permissions

| Action | Super Admin | Department Admin / Dean | Adviser / Moderator | Treasurer | Officer | SDS Staff |
|---|---|---|---|---|---|---|
| Create departments and organizations | Yes | No | No | No | No | No |
| Create Admin and SDS accounts | Yes | No | No | No | No | No |
| Manage unclaimed member roster | All | Own department | No | No | No | No |
| List/manage registered member access | All | Own department's Adviser/Treasurer/Officer accounts | No | No | No | No |
| Transfer accounts to another organization | Yes | No | No | No | No | No |
| Read operational data, reports, analytics | All | Own department | Own organization | Own organization | Own organization | No |
| Create/update/delete budget categories | All | Own department | No | No | No | No |
| Create event proposals | All | Own department | Own organization | Own organization | President, Vice President, Secretary only | No |
| Edit/submit/delete eligible events | All | Own department | Own proposals | Own proposals | Those three positions, own proposals only | No |
| Approve/reject events and expenses | Others' submissions | Others' department submissions | Others' organization submissions | No | No | No |
| Record income and expenses | No | No | No | Own organization | No | No |
| Edit/delete pending expenses, receipts, OCR, purchase completion | No | No | No | Own eligible transactions | No | No |
| Create/edit/delete inventory catalog and confirm drafts | All | Own department | No | No | No | No |
| Record inventory movements | All | Own department | Own organization | Own organization | No | No |
| Upload proposal letters | All | Own department | Own organization | Own organization | Those three positions, own draft/rejected proposals only | No |
| Read proposal letters | All | Own department | Own organization | Own organization | Those three positions, own proposals only | All |
| Read administrative audit history | All | Own department | No | No | No | No |

President, Vice President and Secretary retain `role=officer` and gain proposal
access based on their administrator-managed `position`. Matching ignores case and
collapses whitespace. All other positions (including missing titles, Auditor,
PRO, committee heads and year representatives) remain operational readers.
No position grants finance, inventory, administration or review permissions.
Only `role=treasurer` can record finances, including receipts, OCR and purchase
completion. Admin/Super Admin/Adviser retain financial viewing and independent
review. Personal password and notification actions remain available.

Qualifying Officers create drafts or submit directly to `pending_adviser`, then
Adviser/Moderator review advances to `pending_admin` and Admin review approves.
Owners edit draft/rejected proposals, resubmit them, and delete drafts subject to
references. Rejection/resubmission history and no-self-review rules remain intact.

No role, including Super Admin, can approve or reject its own submissions.
Record ownership is stored on the record; transferring an account does not
transfer historical events, expenses, categories, or inventory.

## Account administration

1. Create the initial Super Admin with python -m scripts.create_super_admin
   or python -m scripts.seed_initial_data --create-admin. There is no public
   HTTP route that creates Super Admins.
2. Super Admin creates departments (POST /departments) and organizations
   (POST /organizations), or uses existing migration organizations.
3. Super Admin creates a department administrator with
   POST /auth/register/admin, providing both department_id and
   organization_id. Admins cannot create other Admin or SDS accounts.
4. Admin adds Adviser, Treasurer, and Officer roster entries with
   POST /cite-members. Its organization and department are used by default;
   Admin may select another organization in its department.
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
Administrative and SDS accounts use separate provisioning routes. Users cannot
alter their own role, scope, or suspension through administrative endpoints.
Super Admin account access cannot be changed through these endpoints; bootstrap
and recovery remain institution-controlled maintenance operations.

Administrative account changes, roster changes, and department/organization
creation write audit records in the same database transaction. Read these using
GET /audit-logs?limit=100&offset=0. There are no audit edit/delete routes.
GET /auth/permissions describes the authenticated user's role and duties, plus
`position`, `can_propose_events`, and `can_record_finance` boolean fields. These
are effective capabilities, so clients must not infer proposal access from role
alone. Managed position changes synchronize claimed roster records and include
the old/new positions in audit history. Existing tokens use current stored access.

## Database rollout

This hierarchy change requires no new migration or automatic account reassignment.
Existing Admin accounts now have department-wide access; assign them only to the
intended department. Existing position assignments determine Officer capabilities.

Apply migrations 001 through 003 if needed, then apply
[004_roles_and_organizations.sql](scripts/004_roles_and_organizations.sql) in the
Supabase SQL Editor before starting this backend version.

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

## Verification

Run .venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app.
Authorization tests use an isolated in-memory database and do not contact
Supabase. They verify member organization isolation, department-wide Admin access,
qualifying Officer proposal ownership/lifecycle, Treasurer-only financial writes,
other Officer write denial, suspension, position/role changes with existing tokens,
user transfers, audit visibility, and self-review.
