"""Shared role/position capabilities and public descriptions of their duties."""

EVENT_PROPOSER_POSITIONS = {"president", "vice president", "secretary"}


def can_propose_events(user) -> bool:
    if user.role in {"super_admin", "admin", "adviser", "treasurer"}:
        return True
    position = " ".join((getattr(user, "position", None) or "").split()).casefold()
    return user.role == "officer" and position in EVENT_PROPOSER_POSITIONS


def can_record_finance(user) -> bool:
    return user.role == "treasurer"

ROLE_POLICY = {
    "super_admin": {
        "scope": "school",
        "responsibility": "Designated school IT administrator, appointed by the institution.",
        "permissions": [
            "Create departments and organizations", "Create organization admins and SDS staff",
            "Manage user access and organization assignments", "View all administrative audit history",
            "Manage operational records except financial recording", "Review events and expenses submitted by others",
        ],
    },
    "admin": {
        "scope": "assigned department, all its organizations",
        "responsibility": "Department Dean or administrator appointed by the Super Admin.",
        "permissions": [
            "Manage the member roster", "List and manage adviser, treasurer, and officer accounts",
            "Suspend or restore member access", "Manage categories and inventory catalog",
            "Manage events, inventory movements, and proposal letters", "Read financial records",
            "Review submissions by others", "View reports, analytics, and organization audit history",
        ],
    },
    "adviser": {
        "scope": "assigned organization and department",
        "responsibility": "Adviser or Moderator overseeing the organization and reviewing event and expense submissions.",
        "permissions": [
            "Read operational records, reports, and analytics", "Create and manage own draft events",
            "Review events and expenses submitted by others", "Record inventory movements",
            "Upload and read proposal letters",
        ],
    },
    "treasurer": {
        "scope": "assigned organization and department",
        "responsibility": "Record financial activity and inventory movements.",
        "permissions": [
            "Read operational records, reports, and analytics", "Create and manage own draft events",
            "Create expenses and manage own pending expenses", "Scan and upload own expense receipts",
            "Record income and inventory movements", "Upload and read proposal letters",
        ],
    },
    "officer": {
        "scope": "assigned organization and department",
        "responsibility": "View organization records for monitoring.",
        "permissions": ["Read operational records, reports, and analytics"],
    },
    "sds_staff": {
        "scope": "school proposal letters",
        "responsibility": "View submitted proposal letters for school oversight.",
        "permissions": ["Read proposal letters"],
    },
}


def effective_role_policy(user) -> dict:
    policy = {**ROLE_POLICY[user.role], "permissions": list(ROLE_POLICY[user.role]["permissions"])}
    proposer = can_propose_events(user)
    if user.role == "officer" and proposer:
        policy["responsibility"] = "Propose events and manage own eligible proposals."
        policy["permissions"] += ["Create and manage own draft or rejected events", "Upload and read own event proposal letters"]
    return {
        "role": user.role,
        "position": getattr(user, "position", None),
        **policy,
        "can_propose_events": proposer,
        "can_record_finance": can_record_finance(user),
    }
