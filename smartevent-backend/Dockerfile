FROM python:3.12-slim

# LibreOffice prints SAP forms (Word only exists on Windows); the fonts stand in for Arial, Times and Calibri.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libreoffice-writer-nogui fonts-liberation fonts-crosextra-carlito \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ app/
COPY certs/ certs/

# Print the SAP template once, plain and with margin comments (as app/services/sap_pdf.py does): this readies
# LibreOffice's profile, and a LibreOffice that cannot print fails the build here instead of every SAP print later.
RUN for pdf in pdf 'pdf:writer_pdf_Export:{"ExportNotesInMargin":{"type":"boolean","value":"true"}}'; do \
        rm -rf /tmp/check \
        && soffice -env:UserInstallation=file:///tmp/smartevent-libreoffice --headless --norestore --nologo --nodefault \
            --convert-to "$pdf" --outdir /tmp/check app/templates/SAS-SDS-FO-020-001-STUDENT-ACTIVITY-PROPOSAL-FORM-V.3.docx \
        && test -s /tmp/check/SAS-SDS-FO-020-001-STUDENT-ACTIVITY-PROPOSAL-FORM-V.3.pdf || exit 1; \
    done && rm -rf /tmp/check

# One worker: the login rate limiter and the SAP print lock live in memory.
# Proxy headers let the rate limiter see the phone's address instead of Render's proxy.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'
