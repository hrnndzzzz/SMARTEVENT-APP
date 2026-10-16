# Excel roster import

Admins and Super Admins can upload an Excel file to add registration-eligible members in one operation. This creates eligibility records; members still complete the existing registration and email-verification flow. It does not create login accounts or send email.

## Workbook

Save as `.xlsx`. Put headers on row 1 of the first worksheet. All six headers are required; their order does not matter. Header matching ignores capitalization and surrounding spaces. Extra columns are ignored. Keep the required columns within the first 256 columns.

| Department | Organization Full Name | Full Name | Email | Role | Position |
| --- | --- | --- | --- | --- | --- |
| CITE | Organization A | Maria Santos | maria@example.com | Officer | Secretary |
| CITE | Organization A | Juan Reyes | juan@example.com | Treasurer | Treasurer |

Replace example department/organization names with existing names from `GET /departments` and `GET /organizations`. Names are matched after trimming spaces and ignoring capitalization. Unknown or ambiguous names are rejected. Organizations must belong to the specified department. An Admin can import only their assigned department and organization; Super Admin can import multiple existing pairs in one file.

- Use plain text in roster cells. Formulas, Excel errors, and numeric/date cells are rejected. Paste formula results as text values first.
- Full Name: required, up to 150 characters. Email: required, valid, up to 150 characters; saved lowercase.
- Role: Officer, Adviser, or Treasurer, ignoring capitalization. Administrative roles cannot be imported.
- Position: optional value, up to 50 characters; its column must still exist.
- Duplicate emails within the workbook or anywhere in the existing roster reject the entire import. Claimed members cannot be overwritten.
- Blank roster rows are ignored, but reported errors retain actual Excel row numbers.
- Maximum upload: 5 MiB (5,242,880 bytes); maximum members: 1,000. Empty rosters are rejected.
- Remove unused formatted rows: at most 10,000 rows below the header are scanned. XLSX expansion is capped at 25 MiB and 1,000 ZIP entries. Macros and legacy `.xls` files are rejected.
- All rows and their audit records are saved together. Any error saves none of the members.

## API

`POST /cite-members/import` with the usual Bearer token. Send a multipart/form-data field named `file`; let the HTTP client set the multipart boundary.

Success: HTTP 201

```json
{
  "filename": "roster.xlsx",
  "inserted_count": 1,
  "members": [
    {"id": "d6715368-a59f-454a-80fa-605868d818a6", "email": "maria@example.com"}
  ]
}
```

Row/header validation failure: HTTP 422

```json
{
  "detail": {
    "code": "roster_import_invalid",
    "errors": [
      {"row": 3, "column": "Email", "message": "Email is already on the roster"}
    ]
  }
}
```

The importer checks workbook structure and cell types before checking database references and member fields. Correct the listed errors and upload again; later validation stages may reveal additional errors. Missing multipart fields use FastAPI's normal validation response.

HTTP 400 means an unsupported, corrupt, empty-byte, or oversized file, or a resource limit was exceeded. HTTP 401/403 means authentication or permissions failed. HTTP 409 with `detail.code = "roster_import_conflict"` means a database conflict prevented the batch; nothing was imported. Other database failures roll back and use the existing safe HTTP 503 response. A retry after a successful upload is rejected as duplicate data.

Each imported member gets a `roster.created` audit record, attributed to the uploader and scoped to the member's department and organization. The uploaded file is not retained.

## Installation and integration

Install the updated backend requirements and restart the service. No database migration is required. Existing manual roster endpoints remain available.

The Flutter upload screen is a separate task. It should submit one workbook, show row/column errors on failure, and refresh the roster after HTTP 201. In development, the endpoint is also available through the backend's `/docs` page.

## Verification

Run `python -m pytest app/test_roster_import.py -q` and then `python -m pytest -q` from the backend folder. Tests use isolated SQLite records, not the configured live database.
