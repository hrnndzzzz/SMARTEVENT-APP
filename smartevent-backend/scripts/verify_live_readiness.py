"""Phase 4 smoke checks. Never prints credentials or customer records.

python -m scripts.verify_live_readiness [--storage-roundtrip] [--ocr-smoke]
Database/API checks use enforced read-only transactions. Optional storage checks
create synthetic UUID-named objects and delete only those objects in finally.
OCR sends synthetic text, never a real receipt. Email checks never send mail.
"""
import argparse
import io
import json
import uuid
from email.utils import parseaddr
from urllib.parse import quote

import httpx
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import and_, event, or_, select, text

from app.config import settings
from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import User
from app.security import create_access_token
from app.services import storage
from app.services.ocr import parse_receipt_text


def read_only(connection):
    connection.exec_driver_sql("SET TRANSACTION READ ONLY")
    connection.exec_driver_sql("SET LOCAL statement_timeout = '15s'")


def database_and_api():
    event.listen(engine, "begin", read_only)
    try:
        with engine.connect() as connection:
            for table in Base.metadata.sorted_tables:
                connection.execute(select(table).limit(0))
            # pg_stat_ssl describes the pooler-to-Postgres hop, not our client socket.
            tls = connection.connection.driver_connection.info.ssl_in_use
            database_hop_tls = connection.execute(text(
                "SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()"
            )).scalar()
            privileged = connection.execute(text(
                "SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname=current_user"
            )).scalar()
        with SessionLocal() as db:
            unassigned = db.query(User.role).filter(
                User.is_active.is_(True), User.is_suspended.is_(False),
                User.must_change_password.is_(False),
                User.role.in_(['admin', 'adviser', 'treasurer', 'officer']),
                or_(User.organization_id.is_(None), User.department_id.is_(None)),
            ).all()
            accounts = db.query(User.id, User.role).filter(
                User.is_active.is_(True), User.is_suspended.is_(False),
                User.must_change_password.is_(False),
                or_(User.role.in_(['super_admin', 'sds_staff', 'signatory']),
                    and_(User.organization_id.is_not(None), User.department_id.is_not(None))),
            ).order_by(User.id).all()
        by_role = {}
        for user_id, role in accounts:
            by_role.setdefault(role, user_id)
        results = {}
        operational = {"super_admin", "admin", "adviser", "treasurer", "officer"}
        with TestClient(app, raise_server_exceptions=False) as client:
            assert client.get('/events').status_code == 401
            for role, user_id in by_role.items():
                headers = {"Authorization": "Bearer " + create_access_token(str(user_id), expires_minutes=5)}
                checks = {}

                def check(path, label=None, expected=200):
                    response = client.get(path, headers=headers)
                    checks[label or path] = response.status_code
                    assert response.status_code == expected, f"{role} {label or path}: {response.status_code}"
                    return response

                check('/auth/me')
                check('/auth/permissions')
                check('/notifications')
                if role in operational:
                    for path in ['/events/requirement-presets', '/events/school-years', '/categories',
                                 '/expenses', '/inventory', '/incomes', '/receipts', '/analytics/dashboard']:
                        check(path)
                    records = check('/events').json()
                    if records:
                        event_path = '/events/' + str(records[0]['id'])
                        for suffix in ['', '/readiness', '/routing', '/logistics', '/compliance', '/post-activity']:
                            expected = 200
                            if suffix == '/logistics' and role == 'officer':
                                expected = 403
                            if suffix in {'/compliance', '/post-activity'} and role in {'treasurer', 'officer'}:
                                expected = 403
                            check(event_path + suffix, '/events/{id}' + suffix, expected)
                    if role in {'admin', 'super_admin'}:
                        for path in ['/users', '/organizations', '/departments', '/cite-members']:
                            check(path)
                else:
                    check('/expenses', expected=403)
                    check('/proposal-letters')
                results[role] = checks
                print(json.dumps({'api_progress': {'role': role, 'checks_passed': len(checks)}}), flush=True)
        return {'status': 'pass', 'model_tables': len(Base.metadata.tables), 'tls_active': bool(tls),
                'pooler_to_database_tls_active': bool(database_hop_tls),
                'privileged_database_login': bool(privileged), 'transactions': 'read-only',
                'http_status_by_role': results,
                'unassigned_ready_accounts_by_role': {role: sum(row.role == role for row in unassigned)
                                                     for role in sorted({row.role for row in unassigned})},
                'roles_without_ready_accounts': sorted((operational | {'sds_staff', 'signatory'}) - by_role.keys())}
    finally:
        event.remove(engine, "begin", read_only)
        engine.dispose()


def storage_check(roundtrip=False):
    results = {}
    for bucket in [settings.supabase_receipts_bucket, settings.supabase_proposal_letters_bucket]:
        metadata = storage._request('GET', 'bucket/' + quote(bucket, safe='')).json()
        assert metadata.get('public') is False, 'Storage bucket is not private'
        result = {'private': True, 'limit_bytes': metadata.get('file_size_limit')}
        if roundtrip:
            buffer = io.BytesIO()
            Image.new('RGB', (20, 20), 'white').save(buffer, format='JPEG')
            content = buffer.getvalue()
            reference = None
            try:
                reference = storage.upload_file(content, 'image/jpeg', bucket, 'jpg', uuid.uuid4(), uuid.uuid4())
                signed = storage.signed_file_url(reference, bucket)
                with httpx.Client(timeout=20, follow_redirects=False) as client:
                    response = client.get(signed)
                    assert response.status_code == 200 and response.content == content, 'Signed download failed'
                    public_url = reference.replace('/object/', '/object/public/', 1)
                    assert client.get(public_url).status_code != 200, 'Anonymous access was allowed'
                result['upload_signed_download_public_denial'] = 'pass'
            finally:
                if reference is not None:
                    _, path = storage.storage_object(reference, bucket)
                    storage._request('DELETE', 'object/' + quote(bucket, safe=''), json={'prefixes': [path]})
                    result['synthetic_object_cleanup'] = 'pass'
        results[bucket] = result
    return results


def email_check():
    sender = parseaddr(settings.resend_from_email or '')[1]
    test_sender = sender.casefold() == 'onboarding@resend.dev'
    test_email = (settings.resend_test_email or '').strip()
    # Authenticates without sending a message. Restricted sending keys may deny listing.
    with httpx.Client(timeout=20, follow_redirects=False) as client:
        response = client.get('https://api.resend.com/domains', headers={
            'Authorization': 'Bearer ' + (settings.resend_api_key or '')})
    verified_sender = False
    if response.status_code == 200:
        domain = sender.rsplit('@', 1)[-1].casefold()
        verified_sender = any(row.get('name', '').casefold() == domain and row.get('status') == 'verified'
                              for row in response.json().get('data', []))
    return {'api_status': response.status_code, 'configured': bool(settings.resend_api_key and sender),
            'development_sender_only': test_sender, 'verified_sender_domain': verified_sender,
            'test_recipient_configured': bool(test_email and 'your_resend_account_email' not in test_email.casefold()),
            'delivery_tested': False}


def ocr_check(smoke=False):
    from google import genai
    from google.genai import types
    with genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=30_000)) as client:
        client.models.get(model=settings.gemini_model)
    result = {'model_available': True, 'model': settings.gemini_model}
    if smoke:
        parsed = parse_receipt_text('SYNTHETIC TEST STORE\n2026-10-05\nNotebook PHP 12.50\nTOTAL PHP 12.50')
        assert parsed['amount'] == 12.5, 'Synthetic total was not parsed correctly'
        result['synthetic_text_extraction'] = 'pass'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--storage-roundtrip', action='store_true')
    parser.add_argument('--ocr-smoke', action='store_true')
    args = parser.parse_args()
    failed = False
    for name, work in [('database_api', database_and_api),
                       ('storage', lambda: storage_check(args.storage_roundtrip)),
                       ('email', email_check), ('ocr', lambda: ocr_check(args.ocr_smoke))]:
        try:
            result = work()
        except Exception as error:
            # Provider exception strings can include URLs, tokens or SQL parameters.
            result = {'status': 'failed', 'error_type': type(error).__name__}
            if isinstance(error, AssertionError):
                result['check'] = str(error)
            failed = True
        print(json.dumps({name: result}), flush=True)
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
