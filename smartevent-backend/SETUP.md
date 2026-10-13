# SMARTEVENT Backend — Local Setup

Get the API running on `localhost` and take it for a test drive.

---

## 1. Prerequisites

- Python 3.11+
- Git
- Access to the shared Supabase project (ask the team for the connection
  string and JWT secret — do not commit these)

---

## 2. Clone and set up the environment

```bash
git clone <repo-url>
cd smartevent-backend

python -m venv .venv

# Windows
.venv\Scripts\activate
# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
```

If there's no `requirements.txt` yet, install directly:

```bash
pip install fastapi "uvicorn[standard]" sqlalchemy psycopg2-binary \
  pydantic-settings "python-jose[cryptography]" "pwdlib[argon2]" email-validator
```

Then freeze it for the team:

```bash
pip freeze > requirements.txt
```

---

## 3. Configure `.env`

Create a `.env` file in the project root (same folder as `app/`):

```env
DATABASE_URL=<ask a teammate for the Supabase pooled connection string>
JWT_SECRET_KEY=<any long random string — must match across the team for shared testing>
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=1440
```

**Do not commit `.env`.** Confirm `.gitignore` has it listed.

---

## 4. Run the server

```bash
uvicorn app.main:app --reload
```

You should see `Application startup complete.` in the terminal.

Open **http://127.0.0.1:8000/docs** — this is Swagger UI, the interactive
API tester. If you see 5 route groups (`auth`, `categories`, `events`,
`expenses`, `inventory`), it's working.

Quick check: **http://127.0.0.1:8000/health** should return `{"status": "ok"}`.

---

## 5. Try it out — full walkthrough in `/docs`

### 5.1 Register test accounts

Expand `POST /auth/register` → **Try it out** → paste each body below →
**Execute**. Do this three times, once per role:

```json
{
  "full_name": "Officer One",
  "email": "officer1@test.com",
  "password": "testpass123",
  "role": "officer",
  "position": "President"
}
```

```json
{
  "full_name": "Adviser One",
  "email": "adviser1@test.com",
  "password": "testpass123",
  "role": "adviser",
  "position": "Faculty Adviser"
}
```

```json
{
  "full_name": "Admin One",
  "email": "admin1@test.com",
  "password": "testpass123",
  "role": "admin",
  "position": "System Admin"
}
```

### 5.2 Log in and authorize

1. Expand `POST /auth/login` → **Try it out**.
2. Fill `username` with `officer1@test.com` and `password` with
   `testpass123` (yes, `username` — that's the OAuth2 form field name,
   even though it's an email).
3. **Execute**. Copy the `access_token` string from the response — don't
   include the quotes.
4. Scroll to the top, click the green **Authorize** button.
5. Paste the token into the box (just the raw token, Swagger adds
   `Bearer ` automatically) → **Authorize** → **Close**.

You're now making requests as Officer One. Repeat login + Authorize
whenever you want to switch users (e.g. to test adviser-only or
admin-only routes) — Swagger only holds one token at a time.

### 5.3 Create a category (needs admin)

Switch to the admin account (5.2, steps 2–5, using `admin1@test.com`).

`POST /categories`:
```json
{
  "name": "Supplies",
  "allocated_budget": 5000,
  "low_balance_threshold": 500
}
```

**Copy the `id` from the response** — you'll need it as `category_id` in
the next steps. This is the one manual copy-paste step; in the real
Flutter app this becomes a dropdown and the ID is never seen by a user.

### 5.4 Create and submit an event (needs officer)

Switch back to the officer account.

`POST /events`:
```json
{
  "category_id": "<paste the category id from 5.3, or use null>",
  "title": "Test Seminar",
  "description": "Walkthrough test event",
  "event_date": "2026-09-01",
  "estimated_cost": 1000,
  "status": "draft"
}
```

Copy the event's `id` from the response. Then:

`POST /events/{event_id}/submit` — paste the event id into the path
param field, **Execute**, no body needed. Status should flip to
`"pending"`.

### 5.5 Approve the event (needs adviser)

Switch to the adviser account.

`POST /events/{event_id}/approve` — same event id, optional body:
```json
{
  "remarks": "Looks good"
}
```

Status should flip to `"approved"`. Check `GET /events/{event_id}/approvals`
to see the logged decision.

### 5.6 File and approve an expense

Still as adviser or switch to officer to create it, then adviser to
approve — same pattern:

`POST /expenses` (as officer):
```json
{
  "category_id": "<the category id from 5.3>",
  "description": "Venue deposit",
  "amount": 500
}
```

`POST /expenses/{expense_id}/approve` (as adviser). Then check
`GET /categories/{category_id}` — `remaining_budget` should have dropped
from 5000 to 4500.

### 5.7 Inventory

`POST /inventory` (as admin):
```json
{
  "item_name": "Plastic Chairs",
  "quantity": 50,
  "unit": "pcs",
  "low_stock_threshold": 10,
  "location": "Storage Room A"
}
```

`POST /inventory/{inventory_id}/transactions` (any logged-in user):
```json
{
  "change_qty": -10,
  "reason": "Checked out for Test Seminar"
}
```

`quantity` should drop from 50 to 40. Try `change_qty: -100` to confirm
the stock guard returns a 409 instead of going negative.

---

## 6. Common issues

| Symptom | Fix |
|---|---|
| `401 Unauthorized` on any route past `/auth` | You didn't click **Authorize**, or your token expired/is from the wrong account. Log in again and re-authorize. |
| `403 Forbidden` | Wrong role for that route (e.g. an officer trying to approve). Switch accounts via 5.2. |
| `500` mentioning `ForeignKeyViolation` | You used a fake/placeholder UUID (e.g. Swagger's default example) instead of a real ID copied from a previous response — usually `category_id` or `event_id`. |
| Server won't start / `ModuleNotFoundError` | Virtual environment isn't activated, or `pip install` didn't finish — re-run step 2. |
| Can't connect to the database | Double-check `DATABASE_URL` in `.env` — get the current one from a teammate, it's not committed to the repo. |
