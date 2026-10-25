# Backend module test report

Date: 22 October 2026

## Result

**452 passed; 0 failed; 0 skipped.** Full backend suite completed in 45.91 seconds with 97 deprecation warnings.

Command: .venv/Scripts/python.exe -m pytest app -q --tb=short --junitxml=tmp/backend-test-results.xml

## Module results

| Test module | Passed |
| --- | ---: |
| app.test_access_management | 32 |
| app.test_auth_security | 28 |
| app.test_core_features | 23 |
| app.test_department_scope | 8 |
| app.test_email | 6 |
| app.test_event_approval_workflow | 14 |
| app.test_event_metadata | 14 |
| app.test_file_access | 33 |
| app.test_financial_management | 24 |
| app.test_financial_reporting | 8 |
| app.test_inventory_management | 30 |
| app.test_operational_security | 20 |
| app.test_phase1_routing | 32 |
| app.test_phase2_compliance | 27 |
| app.test_phase3_closure | 20 |
| app.test_rbac_policy | 41 |
| app.test_request_security | 18 |
| app.test_roster_import | 27 |
| app.test_sap | 31 |
| app.test_storage_security | 16 |

## Correction made

The first run had 451 passes and one SAP PDF assertion failure. PDF text extraction inserted line breaks inside repeated remarks. Reproduction confirmed all 140 remarks were present across seven pages; the assertion now normalizes whitespace before counting. No application behavior was changed in this testing pass.

## Limits and follow-up

- Database-dependent tests use isolated SQLite fixtures, not the deployed PostgreSQL database. Migration deployment, PostgreSQL policies, and real concurrent transactions still require staging checks.
- External services are mocked where used. Real storage uploads, signed URLs, email delivery, and external AI services were not validated against live services.
- The suite exercises PDF generation and extracted text. Visual print layout was not inspected in this run.
- Passing the existing suite is not a claim of full endpoint coverage, load testing, or production readiness.
- Warnings concern Starlette/httpx, Google GenAI Python typing, deprecated HTTP 422 naming, and pypdf page merging. They did not fail this run and should be handled before upgrading those dependencies.
- Frontend files were not edited or tested during this backend testing pass.

Detailed local outputs: tmp/backend-test-results.txt and tmp/backend-test-results.xml.
