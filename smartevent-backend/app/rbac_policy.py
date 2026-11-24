"""Shared role/position capabilities and public descriptions of their duties."""

MEMBER_ROLES = {"officer", "adviser"}
SCHOOL_REVIEWER_ROLES = {"sds_staff"}
# Super Admin is deliberately absent: no roster row or upload can create one.
ROSTER_ROLES = MEMBER_ROLES | {"admin"} | SCHOOL_REVIEWER_ROLES
# Who records money. Advisers and admins review it, so they never record it.
# The Super Admin, the system administrator, may do everything, this included.
FINANCIAL_ROLES = {"officer"}


def manageable_roles(user) -> set[str]:
    """Roles this account may put on the roster or assign through an access change."""
    return {
        "super_admin": ROSTER_ROLES,
        "admin": MEMBER_ROLES,
        "adviser": {"officer"},
    }.get(user.role, set())


def can_propose_events(user) -> bool:
    return user.role in {"super_admin", "admin", "adviser", "officer"}


def can_record_finance(user) -> bool:
    return user.role in FINANCIAL_ROLES | {"super_admin"}

ROLE_POLICY = {
    "super_admin": {
        "scope": "school",
        "responsibility": "Designated school IT administrator, appointed by the institution.",
        "permissions": [
            "Full system access: every action any other role has",
            "Create departments and organizations", "Create organization admins and SDS staff",
            "Manage user access and organization assignments", "View all administrative audit history",
            "Manage all operational and financial records", "Review events and expenses submitted by others",
            "Act for the SDS Office and the Moderator when needed",
        ],
    },
    "admin": {
        "scope": "assigned department, all its organizations",
        "responsibility": "Department Dean or administrator appointed by the Super Admin.",
        "permissions": [
            "Manage the member roster", "List and manage adviser and officer accounts",
            "Suspend or restore member access", "Manage categories and inventory catalog",
            "Manage events, inventory movements, and proposal letters", "Read financial records",
            "Review submissions by others", "View reports, analytics, and organization audit history",
            "Maintain event student rosters; upload and verify pre-activity documents and physical originals",
            "Print attendance sheets, complete events, and manage post-activity evidence and alternative activities",
        ],
    },
    "adviser": {
        "scope": "assigned organization and department",
        "responsibility": "Adviser or Moderator overseeing the organization and reviewing event and expense submissions.",
        "permissions": [
            "Read operational records, reports, and analytics", "Create and manage own draft events",
            "Manage the organization's officer roster and accounts",
            "Manage categories and the inventory catalog", "View organization audit history",
            "Review events and expenses submitted by others", "Record inventory movements",
            "Upload and read proposal letters", "Maintain event student rosters",
            "Assign qualified PICs and verify staff-managed student and logistics evidence",
            "Print attendance sheets, complete events, and record post-activity and alternative learning work",
        ],
    },
    "officer": {
        "scope": "assigned organization and department",
        "responsibility": "Propose events, record financial activity, and handle inventory for the organization.",
        "permissions": [
            "Read operational records, reports, and analytics", "Record inventory stock movements",
            "Create and manage own draft or rejected events", "Upload and read own event proposal letters",
            "Create expenses and manage own pending expenses", "Scan and upload own expense receipts",
            "Record income",
        ],
    },
    "sds_staff": {
        "scope": "school proposal letters and activity proposals the Dean has approved",
        "responsibility": "Review activity proposals once the Dean has approved them, and view submitted proposal letters for school oversight.",
        "permissions": ["Read proposal letters", "Read events with an activity proposal the Dean has approved"],
    },
}


def effective_role_policy(user) -> dict:
    policy = {**ROLE_POLICY[user.role], "permissions": list(ROLE_POLICY[user.role]["permissions"])}
    return {
        "role": user.role,
        "position": getattr(user, "position", None),
        **policy,
        "can_propose_events": can_propose_events(user),
        "can_record_finance": can_record_finance(user),
    }
