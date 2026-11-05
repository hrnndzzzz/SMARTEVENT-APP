# SMARTEVENT-APP
A Capstone Project Presented to the Faculty of the College of Information Technology and Engineering at La Consolacion University Philippines City of Malolos, Bulacan

## Download the app

**[Download SMARTEVENT-arm64-v8a.apk](https://github.com/hrnndzzzz/SMARTEVENT-APP/releases/latest/download/SMARTEVENT-arm64-v8a.apk)**
(the latest release; earlier versions are under [Releases](https://github.com/hrnndzzzz/SMARTEVENT-APP/releases)):
Android 7.0 or newer, 64-bit phones (nearly all phones from the last few years).

1. Download the APK on your phone and open it.
2. Allow installing from this source when Android asks.
3. Open SMARTEVENT and sign in. The app connects to the hosted server by itself;
   there is nothing else to install or set up.

- **The first sign-in of the day can take up to a minute.** The server sleeps when
  nobody has used it for a while and wakes on the first request.
- **Updating?** Download the latest release and install it over the old app.

---

## About SMARTEVENT

SMARTEVENT is a mobile app for student organizations to plan events, get them
approved, and account for every peso and item they use. It replaces paper forms,
spreadsheets and chat-group approvals with one record that every role sees from
their own side: officers propose, advisers and deans review, treasurers record the
money, and the SDS Office clears and signs the official proposal form.

### Who uses it

| Role | What they do in the app |
|---|---|
| **Super Admin** | The school's system administrator. Creates departments, organizations, and Admin, SDS and Signatory accounts; sees everything. |
| **Admin (Dean)** | Runs the organizations in their department: member roster, budget categories, inventory catalog, final event and expense review, audit history. |
| **Adviser / Moderator** | Reviews the organization's event proposals and expenses, records inventory movements, reads reports. |
| **Treasurer** | Records income and expenses, scans receipts, completes purchases. The only role that writes financial records. |
| **Officer** | Reads the organization's records and reports. President, Vice President and Secretary can also create and submit event proposals. |
| **SDS Staff** | The Student Development and Services Office. Reviews, comments on, clears and signs Student Activity Proposals; reads proposal letters school-wide. |
| **Signatory** | An institutional approver (for example a director or the University President) assigned to an event's approval route. |

Every account is tied to one organization and department, so users only see their
own records. No one can approve something they submitted themselves.

### What it does

**Accounts and sign-in**
- Members register with the email their Admin placed on the roster and confirm it
  with a one-time code sent by email. Their role and organization come from the
  roster, not from what they pick.
- Forgot-password recovery by email code, forced password change for new
  admin-created accounts, and a 15-minute lock after five failed sign-ins.

**Events and approvals**
- Propose an event with its school year, semester, scope, budget category and
  details; save it as a draft or submit it.
- The proposal moves through Adviser review, then the Dean, then any assigned
  institutional signatories, in order. A rejected proposal returns with remarks,
  is edited and resubmitted, and every decision stays in its history.
- Event readiness and risk views show what is still missing before an event.

**Student Activity Proposal (SAP) and the SDS Office**
- The organization fills in parts 1 to 3 of the official SAS-SDS-FO-020 form step
  by step on the phone (activity details, budget, support requests and other
  details), with supporting attachments, and submits it.
- The SDS Office reviews it, leaves remarks per part, clears or returns it, and
  signs it with an on-screen signature pad. A proposal can also be withdrawn.
- The app prints the filled form as a PDF, with or without the SDS comments in the
  margin. Each printout carries a verification link that confirms the copy is
  genuine and shows its current revision.

**Budgets, expenses and receipts**
- Budget categories with an allocation, remaining balance and low-balance warning.
- Expenses with item lines, linked to a category and event, reviewed by someone
  other than the person who recorded them. Approval checks the budget first.
- Receipts are photographed and read automatically (OCR): merchant, date, amount
  and items are filled in for the user to check. Duplicate and look-alike receipts
  are flagged for an independent reviewer.

**Income**
- Income per event, classified as registration fees, sponsorship, donation or
  other. Income whose receipt is still under review is shown as withheld.

**Inventory**
- A catalog of the organization's items, with every change recorded as a movement:
  opening balance, acquisition, donation, purchase, issue to an event, return,
  disposal or adjustment.
- Items bought through an approved expense enter stock only after payment and
  delivery are recorded. Stock can never go negative.

**Reports and analytics**
- Dashboard with budgets, event and expense counts, flagged expenses and low stock.
- Spending trends, a flagged-expense queue, and budget suggestions based on past
  events in the same category.
- Category, event and financial reports (weekly, monthly, semester or school year),
  exported as PDF, CSV or a print-ready page.

**Everyday use**
- Notifications for account and proposal activity.
- Offline viewing: the app saves the organization's records on the phone so they
  stay readable without internet.
- Demo mode: hold the heading on the sign-in screen to explore the app as any role
  with sample data. Nothing in demo mode leaves the phone.

### How it is built

| Part | Technology |
|---|---|
| Phone app | Flutter (Android) |
| Server | FastAPI (Python), hosted on Render |
| Database and file storage | Supabase (PostgreSQL and private storage buckets) |
| Receipt reading (OCR) | Google Gemini |
| Email codes | Resend |
