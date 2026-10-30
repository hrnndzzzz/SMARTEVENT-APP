import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/scope.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_cover_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// A Super Admin's proposal never reached the SDS Office, and the app said
/// it had. The event was refused for having no organization, the form went
/// on without one, and sending a proposal with no event "succeeded" on the
/// phone. These pin each of those shut, for every role that may propose.
void main() {
  group('sending never claims success it did not have', () {
    late List<http.Request> sent;

    SapService serviceAnswering(int status, Object body) {
      sent = [];
      return SapService(
        ApiClient(
          httpClient: MockClient((request) async {
            sent.add(request);
            return http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
    }

    test('with a server but no event, submit fails and says why', () async {
      final form = SapForm(service: serviceAnswering(200, {}));

      expect(await form.submit(), isFalse);
      expect(form.error, contains('not on the server'));
      expect(sent, isEmpty);
    });

    test('a 404 on submit is a failure, not a quiet local save', () async {
      final form = SapForm(
        eventId: 'e1',
        service: serviceAnswering(404, {'detail': 'Not Found'}),
      )..seedLocally(); // loaded: a form that never loaded sends nothing

      expect(await form.submit(), isFalse);
      expect(form.error, contains('could not find'));
    });

    test('taking it back is held to the same rule', () async {
      final form = SapForm(service: serviceAnswering(200, {}));
      expect(await form.withdraw(), isFalse);
    });

    test('before the event exists, saving a step still keeps it here', () async {
      // Parts 1 and 2 are written before any event exists, by design.
      final form = SapForm(service: serviceAnswering(200, {}));
      form.updateDetails((d) => d.copyWith(title: 'Written first'));
      expect(await form.saveDetails(), isTrue);
      expect(sent, isEmpty);
    });

    test('the demo, with no server at all, still sends locally', () async {
      final form = SapForm();
      expect(await form.submit(), isTrue);
    });
  });

  group('every proposer role knows whose event it is', () {
    AppState signedIn(
      UserRole role, {
      String? departmentId = 'd1',
      String? organizationId = 'o1',
    }) => AppState()
      ..currentRole = role
      ..currentAccount = Account(
        name: 'Proposer',
        email: 'p@example.test',
        role: role,
        departmentId: departmentId,
        organizationId: organizationId,
      );

    test('a Super Admin chooses, and is never told it is unassigned', () {
      final app = signedIn(
        UserRole.superAdmin,
        departmentId: null,
        organizationId: null,
      );
      expect(app.choosesEventScope, isTrue);
      expect(app.lacksProposerAssignment, isFalse);
    });

    for (final role in [
      UserRole.admin,
      UserRole.adviser,
      UserRole.treasurer,
      UserRole.officer,
    ]) {
      test('${role.name} with an assignment proposes for its own', () {
        final app = signedIn(role);
        expect(app.choosesEventScope, isFalse);
        expect(app.lacksProposerAssignment, isFalse);
      });

      test('${role.name} without one is stopped before the form', () {
        expect(signedIn(role, organizationId: null).lacksProposerAssignment,
            isTrue);
        expect(signedIn(role, departmentId: null).lacksProposerAssignment,
            isTrue);
      });
    }
  });

  group('the cover asks a Super Admin whose activity it is', () {
    final departments = [
      RemoteDepartment(id: 'd1', code: 'CITE', name: 'CITE', description: null),
    ];
    final organizations = [
      RemoteOrganization(id: 'o1', code: 'ACPES', name: 'ACPES', departmentId: 'd1'),
    ];
    List<RemoteOrganization> organizationsIn(String? id) =>
        organizations.where((o) => o.departmentId == id).toList();

    Widget cover(SapForm form, {bool choosing = true}) => MaterialApp(
      theme: AppTheme.light(),
      home: SapCoverScreen(
        form: form,
        onBegin: (_) {},
        departments: choosing ? departments : null,
        organizationsIn: choosing ? organizationsIn : null,
      ),
    );

    bool startEnabled(WidgetTester tester) => tester
        .widget<BrutButton>(find.widgetWithText(BrutButton, 'Start the form'))
        .onPressed != null;

    testWidgets('it cannot start until an organization is chosen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      final form = SapForm();
      form.updateDetails((d) => d.copyWith(setting: SapSetting.onCampus));
      await tester.pumpWidget(cover(form));
      await tester.pumpAndSettle();

      expect(find.text('Scope'), findsOneWidget);
      expect(startEnabled(tester), isFalse);

      form.chooseScope(
        departmentId: 'd1',
        departmentName: 'CITE',
        organizationId: 'o1',
        organizationName: 'ACPES',
      );
      await tester.pumpAndSettle();

      expect(startEnabled(tester), isTrue);
      expect(form.details.organizationName, 'ACPES');
      expect(form.details.department, 'CITE');
    });

    testWidgets('an assigned proposer is not asked at all', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      final form = SapForm();
      form.updateDetails((d) => d.copyWith(setting: SapSetting.onCampus));
      await tester.pumpWidget(cover(form, choosing: false));
      await tester.pumpAndSettle();

      expect(find.text('Scope'), findsNothing);
      expect(startEnabled(tester), isTrue);
    });
  });
}
