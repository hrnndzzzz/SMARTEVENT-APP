# Three questions about roles, answered

The capstone moderator's enhancements **G2, G3 and G4** are questions
rather than features:

- **G2** — identify the super administrator and its permissions
- **G3** — the organizational administrator hierarchy
- **G4** — confirm whether officers are view-only

All three are settled in code, in the backend's hierarchy work of 25
October 2026. The authority is
[`smartevent-backend/ROLES_AND_PERMISSIONS.md`](../smartevent-backend/ROLES_AND_PERMISSIONS.md)
and `app/rbac_policy.py`; this page answers the three questions in the
moderator's own terms and points at where each answer is enforced, so
there are not two policies to keep in step.

---

## G2 — Who the super administrator is, and what it may do

**A school IT administrator appointed by the institution.** The software
does not and cannot choose that person; the account belongs to whoever
the school names.

It is the only role with **global operational access** — every
department, every organization. Specifically it may:

- create departments and organizations
- create organization admins and SDS staff
- manage user access and organization assignments
- read all administrative audit history
- manage operational records, and review what others submit

**It may not record money.** Recording finances is the Treasurer's,
and only the Treasurer's — the Super Admin can read financial records
and review them independently, but cannot create them. That separation
is deliberate: whoever records the money is not the person who approves
it, and a global administrator is no exception.

Enforced by `can_record_finance` in `rbac_policy.py`, which answers true
for `role == 'treasurer'` and nothing else.

---

## G3 — The hierarchy

```
Super Admin                      the school's IT administrator, platform-wide
  └── Admin (Dean)               one department, every organization in it
        └── Adviser / Moderator  one organization
              └── President      one organization
                    └── other officers
```

Alongside it, two roles that sit outside the chain rather than in it:

- **Treasurer** — a financial responsibility, not a rank. A Treasurer
  does not supervise officers; they record money, which nobody above
  them in the chain may do.
- **SDS Staff** and **Signatories** — institutional oversight. SDS Staff
  read proposal letters across the whole school and nothing else: no
  events, finances, inventory, reports, accounts, rosters or audit
  history. Signatories hold final approval and no general operational
  access.

**Adviser and Moderator are the same role.** They share the `adviser`
permissions exactly; the two words are the same job under two names.

On scope: every organization belongs to one department, and every
Admin, Adviser, Treasurer and Officer account belongs to one
organization and that organization's department. An **Admin covers
every organization in their department**; an Adviser, Treasurer or
Officer is confined to their own organization. A missing assignment
fails closed rather than opening up.

---

## G4 — Are officers view-only?

**No.** Every officer, whatever position the administrator records,
may propose events: create and manage their own draft or returned
events, submit them, and upload the proposal letters for their own
events. For a SAP proposal they may prepare Parts 1 to 3, manage the
supporting attachments, and submit into the paper workflow. Officers
also record stock movements and add or remove inventory items; removing
an item that has history archives it instead of erasing it.

Three things hold whatever the position says:

1. **No officer gets finance, administration or review.** An officer
   cannot record an expense.
2. **Nobody reviews their own proposal**, at any rank.
3. **SDS-only work stays with the SDS Office** — clearance, signing,
   paper evidence and closeout.

Enforced by `can_propose_events` in `rbac_policy.py`, and
`/auth/permissions` reports the answer per account so the app asks
rather than guesses.

---

## Why the app asks rather than decides

The client used to keep its own copy of this policy in `UserRole` and
the copies drifted — the app allowed administrators to record money
after the backend had stopped them. It now reads `can_propose_events`
and `can_record_finance` from `/auth/permissions` and falls back to the
role only where the server gives no answer, so a policy change on the
backend reaches the app without a release.

See `AppState.mayProposeEvents` and `AppState.mayRecordFinance`.
