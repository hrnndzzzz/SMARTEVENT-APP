"""Sends transactional OTP emails through Resend."""

from email.utils import parseaddr

import resend
from resend.exceptions import ResendError

from app.config import settings


class EmailError(Exception):
    """Raised when sending an email fails for any reason."""


def send_email(to_email: str, subject: str, body_text: str, *, idempotency_key: str | None = None) -> None:
    if not settings.resend_api_key:
        raise RuntimeError("Resend is not configured. Set RESEND_API_KEY.")
    if not settings.resend_from_email:
        raise RuntimeError(
            "Resend sender is not configured. Set RESEND_FROM_EMAIL to an address on a verified domain."
        )
    if parseaddr(settings.resend_from_email)[1].casefold() == "onboarding@resend.dev":
        test_email = (settings.resend_test_email or "").strip()
        if not test_email or "your_resend_account_email" in test_email.casefold():
            raise RuntimeError(
                "Replace RESEND_TEST_EMAIL with the email address associated with your Resend account."
            )
        if to_email.strip().casefold() != test_email.casefold():
            raise RuntimeError(
                "The Resend development sender can only deliver to RESEND_TEST_EMAIL."
            )

    resend.api_key = settings.resend_api_key
    try:
        params = {
                "from": settings.resend_from_email,
                "to": [to_email],
                "subject": subject,
                "text": body_text,
            }
        if idempotency_key:
            resend.Emails.send(params, {"idempotency_key": idempotency_key})
        else:
            resend.Emails.send(params)
    except ResendError as exc:
        raise EmailError(f"Failed to send email to {to_email}: {exc}") from exc


def send_otp_email(to_email: str, full_name: str, otp_code: str, purpose: str) -> None:
    """
    purpose: 'initial_setup' | 'password_reset' — only changes the
    wording, both send the same 6-digit code.
    """
    if purpose == "registration":
        subject = "Your SMARTEVENT registration verification code"
        body = (
            f"Hi {full_name},\n\n"
            f"Thank you for registering with SMARTEVENT. Your registration verification code is:\n\n"
            f"    {otp_code}\n\n"
            f"Please enter this code within {settings.otp_expiry_minutes} minutes to verify your account and activate it.\n\n"
            f"If you did not register for SMARTEVENT, you can safely ignore this email.\n"
        )
    elif purpose == "initial_setup":
        subject = "Your SMARTEVENT temporary password"
        body = (
            f"Hi {full_name},\n\n"
            f"Your SMARTEVENT account has been created. Your temporary "
            f"password is:\n\n"
            f"    {otp_code}\n\n"
            f"Log in with this password within {settings.otp_expiry_minutes} "
            f"minutes, then set a new password right away — this "
            f"temporary password stops working once it expires.\n\n"
            f"If you weren't expecting this account, contact your "
            f"administrator.\n"
        )
    else:
        subject = "Your SMARTEVENT password reset code"
        body = (
            f"Hi {full_name},\n\n"
            f"You requested a password reset. Your one-time code is:\n\n"
            f"    {otp_code}\n\n"
            f"This code expires in {settings.otp_expiry_minutes} minutes. "
            f"If you didn't request this, you can safely ignore this email "
            f"— your password has not been changed.\n"
        )

    send_email(to_email, subject, body)
