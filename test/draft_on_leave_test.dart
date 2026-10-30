import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// "Save as draft" on the way out kept less than Save did. Part 1 sent
/// none of the text typed since the last Next, and Part 3 none of its
/// notes and none of the classes it interrupts.
void main() {
  late List<http.Request> sent;

  /// A draft with nothing in it yet.
  SapService server() {
    sent = [];
    return SapService(
      ApiClient(
        httpClient: MockClient((request) async {
          sent.add(request);
          final body = request.url.path.endsWith('/attachments')
              ? <Object>[]
              : {
                  'id': 'p1',
                  'event_id': 'e1',
                  'state': 'draft',
                  'version': 1,
                  'revision_no': 0,
                  'details': <String, Object>{},
                  'collections': {
                    'program-flow': <Object>[],
                    'budget-items': <Object>[],
                    'support-requests': <Object>[],
                    'affected-classes': <Object>[],
                  },
                };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  }

  /// The body of the last request of this kind, or null if none was sent.
  Map<String, Object?>? lastSent(String method, String pathEnd) {
    final match = sent.where(
      (r) => r.method == method && r.url.path.endsWith(pathEnd),
    );
    return match.isEmpty
        ? null
        : jsonDecode(match.last.body) as Map<String, Object?>;
  }

  Widget host(Widget child) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(BrutTextField, label),
    matching: find.byType(TextField),
  );

  Future<void> saveDraftOnLeaving(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as draft'));
    await tester.pumpAndSettle();
  }

  testWidgets('Part 1 keeps what was typed since the last Next', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final form = SapForm(eventId: 'e1', service: server());
    await form.load();

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();
    await tester.enterText(field('ACTIVITY TITLE'), 'Hack the Future');
    await saveDraftOnLeaving(tester);

    final details = lastSent('PATCH', '/sap-proposal')?['details'] as Map?;
    expect(details?['title'], 'Hack the Future');
    // A box nobody has filled in is left out. Sent as '' it fails the
    // server's one-character minimum, and the whole draft is refused.
    expect(details, isNot(contains('venue')));
    expect(details, isNot(contains('department_type')));
  });

  testWidgets('Part 3 keeps its notes and the classes it interrupts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final form = SapForm(eventId: 'e1', service: server());
    await form.load();
    form.setAffectedClasses([
      SapAffectedClass(
        yearLevel: 'BSCpE 3',
        subject: 'Data & Digital',
        classDate: DateTime(2026, 10, 28),
        start: const SapTime(7, 0),
        end: const SapTime(12, 0),
        professor: 'Engr. Glazen Perez',
      ),
    ]);

    await tester.pumpWidget(host(SapPart3Screen(form: form)));
    await tester.pumpAndSettle();
    await tester.enterText(field('FOCUS'), 'Securing code from day one.');
    await saveDraftOnLeaving(tester);

    final details = lastSent('PATCH', '/sap-proposal')?['details'] as Map?;
    expect(
      details?['additional_information'],
      contains('Focus: Securing code from day one.'),
    );
    expect(lastSent('PUT', '/affected-classes')?['items'], hasLength(1));
  });
}
