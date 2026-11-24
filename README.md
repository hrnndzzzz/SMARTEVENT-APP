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

SMARTEVENT puts all of that into one shared record on the phone. Officers propose and
record the money, advisers and deans review, and the SDS Office clears and signs the
official proposal form. Each person sees the same event from their own side,
every decision is kept, and the paperwork prints itself when it is needed.

## Features at a glance

- **Event proposals and approvals:** submit an event and follow it step by step,
  from the Adviser to the Dean to the SDS Office. Returned proposals come back
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
| **Officer** | Proposes events, records income and expenses, scans receipts and moves stock. The treasurer of an organization is an officer whose position says so. |
| **SDS Staff** | Reviews, clears and signs Student Activity Proposals. |

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

**Buying supplies.** The officer keeping the money photographs a receipt for ₱1,250 of
tarpaulin and markers. The app fills in the store, date and items, and the officer
checks them and saves the expense under the event's budget. The Adviser approves it, the remaining
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
  minute; open `https://api.smartevent.date/health` before a demo to wake it.
- **SAP PDFs are printed with LibreOffice there**, not Word, so check a printout
  after each change to the SAP form.
- **The app points at it** when built with
  `flutter build apk --release --target-platform android-arm64 --dart-define=SMARTEVENT_API_BASE_URL=https://api.smartevent.date --dart-define=SMARTEVENT_RELEASE_TAG=<tag>`,
  or by typing the address in the app's Settings → Backend. `<tag>` is the GitHub
  release the APK goes out as (such as `v1.0.4`). The app compares it with the latest
  release to offer updates, so it must match; a build without it never checks.
- **A testing build that installs beside the real app:** add
  `--android-project-arg=smarteventDev=true` and leave the release tag off. It
  shows on the phone as SMARTEVENT-DEV (`com.lcup.smartevent.smartevent.dev`),
  with its own sign-in and data, and never asks to update.
- **Signing: an APK anybody else installs needs the shared release key.** Android
  refuses an update signed by a different key than the installed copy, and each
  machine generates its own debug keystore — so two of us building "release" APKs
  produced builds that would not install over each other
  (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), only a reinstall that wipes the data.

  One key, held by both of us, fixes it for good. **Do not generate a fresh one.**
  Every release on the download link since v1.0.14 — v1.0.14, v1.0.15, v1.0.16 and
  v1.0.17 — is signed by the same certificate, `083d0485…cb909756`, which is
  Jasper's `.android/debug.keystore` (alias `androiddebugkey`, valid to 2056). A
  new key would mean every one of those phones uninstalling once; adopting that
  keystore as the shared release key means the next update simply installs.

  So the shared key is a copy of that file, taken out of `.android` where a tool
  cleanup could wipe it, and given a real password. Changing a keystore's password
  leaves the key itself untouched, so updates still install:

  ```
  keytool -storepasswd -keystore <copy>
  keytool -keypasswd -alias androiddebugkey -keystore <copy>
  ```

  Two things follow from using a debug certificate. Google Play refuses one named
  `CN=Android Debug`, so publishing there later means a new key and one uninstall
  at that point — not before. And Sean's Mac has a different debug key
  (`2025da6a…987c010c`, which signed v1.0.12), so a handset carrying a Mac-built
  APK needs one uninstall at the changeover. That is one phone, not the cohort.

  Then write `key.properties`, which is gitignored and must never be committed.
  Put it at `~/.smartevent/key.properties` rather than in `android/`: worktrees
  and second clones each have their own `android/`, and an untracked file is in
  none of them, so a release built in one would quietly fall back to the debug
  key. The home copy serves every checkout on the machine; a copy in `android/`
  still wins if one project needs a different key.

  ```
  storeFile=/Users/you/smartevent-release.jks
  storePassword=...
  keyAlias=smartevent
  keyPassword=...
  ```

  Send the `.jks` and the two passwords to each other privately — not through the
  repository, an issue, or a pull request. Keep a copy somewhere you will not lose
  it: lose the key and no future build can ever update an installed app.

  `storeFile` should be an absolute path. A relative one is read against the
  `android/` directory of whichever checkout is building, which is only right
  when the key.properties sits beside it.

  Without `key.properties` the build still works and falls back to this machine's
  debug key, which is fine for `flutter run` and for your own handset. It is not
  fine for the APK on the website. The build prints which key it used, but only
  when Gradle configures from cold — a cached configuration prints nothing — so
  the answer that is always true is to read the APK:
  `apksigner verify --print-certs <apk>`. `CN=Android Debug` means it was the
  fallback.

  Everyone holding the current debug-signed build has to uninstall once when the
  first properly signed APK goes out, so do that changeover before handing the
  link around rather than after.
- `DATABASE_URL` must be Supabase's **Session pooler** address (Render has no
  IPv6) ending in `?sslmode=verify-full&sslrootcert=/srv/certs/supabase-ca.crt`.
  The certificate comes from Supabase → Project Settings → Database → SSL.

