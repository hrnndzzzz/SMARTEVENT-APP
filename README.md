# SMARTEVENT

**One app for student organizations to plan events, get them approved, and account
for every peso and item they use.**

A Capstone Project Presented to the Faculty of the College of Information Technology
and Engineering at La Consolacion University Philippines, City of Malolos, Bulacan.

**[Download the latest app (Android APK)](https://github.com/hrnndzzzz/SMARTEVENT-APP/releases/latest/download/SMARTEVENT-arm64-v8a.apk)**
· [All releases](https://github.com/hrnndzzzz/SMARTEVENT-APP/releases)

---

## Why it exists

Running a student event today means paper proposal forms passed from office to office,
budgets kept in personal spreadsheets, receipts stuffed in envelopes, and approvals
buried in group chats. Forms get lost, nobody knows who is holding a proposal, and at
the end of the term it is hard to show where the money went.

SMARTEVENT puts all of that into one shared record on the phone. Officers propose,
advisers and deans review, treasurers record the money, and the SDS Office clears and
signs the official proposal form. Each person sees the same event from their own side,
every decision is kept, and the paperwork prints itself when it is needed.

## Features at a glance

- **Event proposals and approvals:** submit an event and follow it step by step,
  from the Adviser to the Dean to any other signatories. Returned proposals come back
  with remarks so you can fix them and resubmit.
- **Official SDS proposal form:** fill in the Student Activity Proposal (SAS-SDS-FO-020)
  on your phone. The SDS Office comments on it, clears it and signs it on screen, and
  the app prints it as a PDF that anyone can check is genuine.
- **Budgets and expenses:** set a budget per category, record expenses against it,
  and get warned before money runs low. Someone other than the person who recorded an
  expense has to approve it.
- **Receipt scanning:** take a photo of a receipt and the app fills in the store,
  date, amount and items for you. Duplicate receipts are flagged.
- **Income:** record registration fees, sponsorships and donations for each event.
- **Inventory:** keep a list of the organization's items and every time something is
  bought, lent to an event, returned or disposed of.
- **Reports:** a dashboard plus weekly, monthly, semester or school-year reports,
  saved as PDF or CSV.
- **Works offline:** your organization's records stay readable without internet.
- **Demo mode:** try every role with sample data, no account needed.

## Who uses it

| Role | In one line |
|---|---|
| **Super Admin** | Sets up departments, organizations and staff accounts; sees everything. |
| **Admin (Dean)** | Runs the organizations in their department and gives final approval. |
| **Adviser / Moderator** | Reviews proposals and expenses and manages their own organization's roster, budgets and items. |
| **Treasurer** | Records income and expenses and scans receipts. |
| **Officer** | Reads the organization's records. The President, Vice President and Secretary can also propose events. |
| **SDS Staff** | Reviews, clears and signs Student Activity Proposals. |
| **Signatory** | Approves events they are assigned to, such as a director or the University President. |

Everyone only sees their own organization's records, and no one can approve something
they submitted themselves.

## How to use it

1. **Install.** Download the APK on an Android phone (Android 7.0 or newer), open it, and
   allow installing from this source when asked.
2. **Register.** Sign up with the email your Admin or Adviser put on the roster, then type
   the code sent to that email. Your role and organization are set for you.
3. **Sign in and go.** The app connects to the school's server by itself. There is
   nothing else to set up.

> The first sign-in of the day can take up to a minute while the server wakes up.
> The app keeps itself up to date: when a new release is out it asks you to install it,
> downloads it, and opens the phone's installer. The first time, allow installing from
> SMARTEVENT when asked.

## Examples

**Proposing an event.** The org President creates a "Foundation Week Booth" event with
its date, budget category and details, and submits it. The Adviser approves it, the Dean
approves it, and the President gets a notification at each step. If the Dean returns it
asking for a smaller budget, the President edits it and sends it again, and the earlier
decision stays in the history.

**Getting the SDS form signed.** The organization fills in the Student Activity Proposal
one part at a time and attaches its supporting files. SDS Staff leave a remark on the
budget part and return it. Once it is fixed, SDS clears it and signs it on screen, and
the organization prints the signed PDF to submit.

**Buying supplies.** The Treasurer photographs a receipt for ₱1,250 of tarpaulin and
markers. The app fills in the store, date and items, and the Treasurer checks them and
saves the expense under the event's budget. The Adviser approves it, the remaining
budget drops by ₱1,250, and the markers are added to inventory once delivery is recorded.

## How it is built

| Part | Tool |
|---|---|
| Phone app | Flutter (Android) |
| Server | FastAPI (Python), hosted on Render |
| Database and files | Supabase |
| Receipt reading | Google Gemini |
| Email codes | Resend |

For the full picture of how each process flows, see the [flowcharts](docs/flowcharts.md).

## Hosted server (Render)

The backend can run on Render's free tier from `smartevent-backend/Dockerfile`
(set up once from `render.yaml`: Render Dashboard → New → Blueprint).

- **It sleeps after 15 minutes idle.** The first request after that takes about a
  minute; open `https://<service>.onrender.com/health` before a demo to wake it.
- **SAP PDFs are printed with LibreOffice there**, not Word, so check a printout
  after each change to the SAP form.
- **The app points at it** when built with
  `flutter build apk --release --target-platform android-arm64 --dart-define=SMARTEVENT_API_BASE_URL=https://<service>.onrender.com --dart-define=SMARTEVENT_RELEASE_TAG=<tag>`,
  or by typing the address in the app's Settings → Backend. `<tag>` is the GitHub
  release the APK goes out as (such as `v1.0.4`). The app compares it with the latest
  release to offer updates, so it must match; a build without it never checks.
- `DATABASE_URL` must be Supabase's **Session pooler** address (Render has no
  IPv6) ending in `?sslmode=verify-full&sslrootcert=/srv/certs/supabase-ca.crt`.
  The certificate comes from Supabase → Project Settings → Database → SSL.

