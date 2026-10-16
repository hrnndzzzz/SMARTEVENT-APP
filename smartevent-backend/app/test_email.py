import pytest
import resend

from app.config import settings
from app.services.email import EmailError, send_email


def test_send_email_uses_resend_settings_and_plain_text(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "test-api-key")
    monkeypatch.setattr(settings, "resend_from_email", "SMARTEVENT <test@example.com>")
    monkeypatch.setattr(resend, "api_key", None)
    sent = {}

    def fake_send(params):
        sent.update(params)
        return {"id": "test-email-id"}

    monkeypatch.setattr(resend.Emails, "send", fake_send)

    send_email("member@example.com", "Registration code", "Your code is 123456")

    assert resend.api_key == "test-api-key"
    assert sent == {
        "from": "SMARTEVENT <test@example.com>",
        "to": ["member@example.com"],
        "subject": "Registration code",
        "text": "Your code is 123456",
    }


def test_send_email_fails_when_resend_is_not_configured(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", None)
    monkeypatch.setattr(settings, "resend_from_email", "SMARTEVENT <test@example.com>")

    with pytest.raises(RuntimeError, match="RESEND_API_KEY"):
        send_email("member@example.com", "Registration code", "Your code is 123456")


def test_send_email_wraps_resend_delivery_errors(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "test-api-key")
    monkeypatch.setattr(settings, "resend_from_email", "SMARTEVENT <test@example.com>")

    def fail_send(params):
        raise resend.exceptions.ResendError(500, "test_error", "delivery failed", "")

    monkeypatch.setattr(resend.Emails, "send", fail_send)

    with pytest.raises(EmailError):
        send_email("member@example.com", "Registration code", "Your code is 123456")


def test_resend_development_sender_only_delivers_to_test_email(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "test-api-key")
    monkeypatch.setattr(settings, "resend_from_email", "SMARTEVENT <onboarding@resend.dev>")
    monkeypatch.setattr(settings, "resend_test_email", "account@example.com")

    with pytest.raises(RuntimeError, match="RESEND_TEST_EMAIL"):
        send_email("other@example.com", "Registration code", "Your code is 123456")


def test_resend_development_sender_rejects_placeholder_test_email(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "test-api-key")
    monkeypatch.setattr(settings, "resend_from_email", "SMARTEVENT <onboarding@resend.dev>")
    monkeypatch.setattr(
        settings,
        "resend_test_email",
        "your_resend_account_email@gmail.com",
    )

    with pytest.raises(RuntimeError, match="Replace RESEND_TEST_EMAIL"):
        send_email(
            "your_resend_account_email@gmail.com",
            "Registration code",
            "Your code is 123456",
        )


def test_resend_development_sender_allows_configured_test_email(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "test-api-key")
    monkeypatch.setattr(settings, "resend_from_email", "SMARTEVENT <onboarding@resend.dev>")
    monkeypatch.setattr(settings, "resend_test_email", "account@example.com")
    sent = {}

    def fake_send(params):
        sent.update(params)
        return {"id": "test-email-id"}

    monkeypatch.setattr(resend.Emails, "send", fake_send)

    send_email("Account@example.com", "Registration code", "Your code is 123456")

    assert sent["to"] == ["Account@example.com"]