import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/models/user_profile.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/brut.dart';

import 'off_campus_test.dart' show formSet, host;

/// The department is "taken from the account", which a form opened from
/// an event never did, and Part 1 copied its blank box over it on save.
void main() {
  testWidgets('a department filled after Part 1 opened survives the save', (
    tester,
  ) async {
    // Part 1 used to copy a hidden, never-updated field over it.
    final form = formSet(SapSetting.onCampus);
    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();
    form.updateDetails((d) => d.copyWith(department: 'CITE'));

    tester
        .widget<BrutButton>(find.widgetWithText(BrutButton, 'Save'))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(form.details.department, 'CITE');
  });

  testWidgets('an existing draft takes the department from the account', (
    tester,
  ) async {
    // The form opened from an event never went through the flow that
    // fills it, so its Part 1 sent a blank department.
    final app = AppState()
      ..currentAccount = Account(
        name: 'Demo Treasurer',
        email: 't@example.com',
        role: UserRole.treasurer,
        departmentId: 'd1',
        organizationId: 'o1',
        organizationName: 'ACPES',
        departmentName: 'CITE',
      );
    addTearDown(app.dispose);
    final form = SapForm(
      eventId: 'e1',
      service: SapService(
        ApiClient(
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode(
                request.url.path.endsWith('/attachments')
                    ? []
                    : {'id': 'p1', 'event_id': 'e1', 'state': 'draft', 'version': 2},
              ),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
        ],
        child: host(SapFormScreen(form: form)),
      ),
    );
    await tester.pumpAndSettle();

    expect(form.version, 2);
    expect(form.details.department, 'CITE');
    expect(form.details.organizationName, 'ACPES');
  });

  test('the account names its own department', () {
    // Only an Admin may list departments, so a student officer needs the
    // name on `/auth/me` for Part 1's Department to be filled at all.
    final me = UserProfile.fromJson({
      'id': 'u1',
      'full_name': 'Sean Reyes',
      'email': 'sean@example.edu',
      'role': 'officer',
      'department_id': 'd1',
      'department_name': 'CITE',
      'is_active': true,
      'must_change_password': false,
      'created_at': '2026-10-01T00:00:00Z',
    });

    expect(me.departmentName, 'CITE');
    expect(UserProfile.fromJson(me.toJson()).departmentName, 'CITE');
  });
}
