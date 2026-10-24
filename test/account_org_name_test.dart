import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/user_profile.dart';

/// Only Admin and above may call `/organizations`, so before the backend
/// named the organization on `/auth/me` (24 Oct) a student officer could
/// not turn their own organization id into a name — and they are the
/// people who fill in the SAP form's Part 1, which opened blank.
void main() {
  Map<String, dynamic> row(Map<String, dynamic> extra) => {
    'id': 'u1',
    'full_name': 'Sean Reyes',
    'email': 'sean@example.edu',
    'role': 'officer',
    'position': 'President',
    'department_id': 'd1',
    'is_active': true,
    'must_change_password': false,
    'created_at': '2026-10-01T00:00:00Z',
    ...extra,
  };

  test('an officer learns their own organization by name', () {
    final me = UserProfile.fromJson(
      row({'organization_id': 'o1', 'organization_name': 'JPSSITE'}),
    );

    expect(me.organizationId, 'o1');
    expect(me.organizationName, 'JPSSITE');
  });

  test('an older backend sends the id alone, and that still parses', () {
    // The field is new, so signing in against a backend without it must
    // not fail — the form falls back to the organization list there.
    final me = UserProfile.fromJson(row({'organization_id': 'o1'}));

    expect(me.organizationId, 'o1');
    expect(me.organizationName, isNull);
  });

  test('an unscoped account has neither', () {
    final me = UserProfile.fromJson(row({'role': 'super_admin'}));

    expect(me.organizationId, isNull);
    expect(me.organizationName, isNull);
  });
}
