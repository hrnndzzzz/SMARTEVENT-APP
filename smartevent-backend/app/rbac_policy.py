"""Public descriptions of the roles supported by the backend.

Authorization still runs in dependencies and record scope checks. This metadata
is exposed so clients can explain roles without inventing their own hierarchy.
"""

ROLE_POLICY = {
    "super_admin": {
        "scope": "school",
        "responsibility": "Designated school IT administrator, appointed by the institution.",
        "permissions": [
            "Create departments and organizations", "Create organization admins and SDS staff",
            "Manage user access and organization assignments", "View all administrative audit history",
            "Manage all operational records", "Review events and expenses submitted by others",
        ],
    },
    "admin": {
        "scope": "assigned organization and department",
        "responsibility": "Organization administrator appointed by the Super Admin.",
        "permissions": [
            "Manage the member roster", "List and manage adviser, treasurer, and officer accounts",
            "Suspend or restore member access", "Manage categories and inventory catalog",
            "Manage events, expenses, income, inventory movements, and proposal letters",
            "Review submissions by others", "View reports, analytics, and organization audit history",
        ],
    },
    "adviser": {
        "scope": "assigned organization and department",
        "responsibility": "Review event proposals and expense submissions.",
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
