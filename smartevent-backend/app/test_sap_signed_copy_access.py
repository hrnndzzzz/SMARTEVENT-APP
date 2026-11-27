import hashlib

from app.models_sap import SAPFinalCopy, SAPProposal, SAPRevision
from app.test_access_management import system


def add_signed_copy(db, event, uploader):
    proposal = SAPProposal(event_id=event.id, state='approved', revision_no=1)
    db.add(proposal)
    db.flush()
    pdf = b'%PDF-signed-copy'
    revision = SAPRevision(
        proposal_id=proposal.id,
        revision_no=1,
        snapshot={},
        printable_pdf=pdf,
        pdf_sha256=hashlib.sha256(pdf).hexdigest(),
        verification_token='signed-copy-test-token',
        submitted_by=uploader.id,
    )
    db.add(revision)
    db.flush()
    db.add(SAPFinalCopy(
        revision_id=revision.id,
        storage_ref='https://storage.example.com/scan.pdf',
        sha256=hashlib.sha256(pdf).hexdigest(),
        uploaded_by=uploader.id,
    ))
    db.commit()


def test_authorized_non_sds_viewer_can_download_signed_copy(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    event = resources[0]['events']
    add_signed_copy(db, event, users['sds_staff'])
    monkeypatch.setattr(
        'app.routers.sap.storage.signed_file_url',
        lambda ref: ref + '?token=temporary',
    )

    login('officer')
    response = client.get(f'/events/{event.id}/sap-proposal/final-signed-copy')

    assert response.status_code == 200, response.text
    assert response.json() == {
        'url': 'https://storage.example.com/scan.pdf?token=temporary',
        'expires_in': 300,
        'sha256': hashlib.sha256(b'%PDF-signed-copy').hexdigest(),
    }


def test_foreign_non_sds_viewer_cannot_download_signed_copy(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    event = resources[1]['events']
    add_signed_copy(db, event, users['sds_staff'])
    monkeypatch.setattr('app.routers.sap.storage.signed_file_url', lambda ref: ref)

    login('officer')
    response = client.get(f'/events/{event.id}/sap-proposal/final-signed-copy')

    assert response.status_code == 403


def test_missing_signed_copy_returns_not_found(system):
    client, db, users, orgs, resources, login = system
    event = resources[0]['events']
    proposal = SAPProposal(event_id=event.id, state='approved', revision_no=1)
    db.add(proposal)
    db.flush()
    db.add(SAPRevision(
        proposal_id=proposal.id,
        revision_no=1,
        snapshot={},
        printable_pdf=b'%PDF-signed-copy',
        pdf_sha256='a' * 64,
        verification_token='missing-signed-copy-token',
        submitted_by=users['officer'].id,
    ))
    db.commit()

    login('officer')
    response = client.get(f'/events/{event.id}/sap-proposal/final-signed-copy')

    assert response.status_code == 404
