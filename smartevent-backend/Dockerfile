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

# One worker: the login rate limiter and the SAP print lock live in memory.
# Proxy headers let the rate limiter see the phone's address instead of Render's proxy.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'
