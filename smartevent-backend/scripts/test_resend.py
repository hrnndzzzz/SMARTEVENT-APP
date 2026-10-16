"""Send a non-OTP test message to the configured Resend test mailbox."""

import sys

from app.config import settings
from app.services.email import EmailError, send_email


def main() -> None:
    if not settings.resend_test_email:
        print("Set RESEND_TEST_EMAIL to the email used for your Resend account.", file=sys.stderr)
        sys.exit(1)

    try:
        send_email(
            settings.resend_test_email,
            "SMARTEVENT Resend Test",
            "Your SMARTEVENT Resend email configuration is working.",
        )
    except (RuntimeError, EmailError) as exc:
        print(f"Resend test failed: {exc}", file=sys.stderr)
        sys.exit(1)

    print("Resend accepted the test email. Check your inbox and the Resend Emails dashboard.")


if __name__ == "__main__":
    main()