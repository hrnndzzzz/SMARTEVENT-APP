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
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// A proposer typed the programme, and the server said at submission that
/// there was none. Every save answers with the whole proposal, and taking
/// that answer whole replaced the rows not yet sent with the server's
/// empty list, which the next save then sent.
void main() {
  late List<http.Request> sent;

  /// A draft with nothing in it yet, which is what the server answers with
  /// until the programme reaches it.
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

  /// The rows in every programme sent, oldest first.
  List<List<Object?>> programmesSent() => [
    for (final r in sent)
      if (r.method == 'PUT' && r.url.path.endsWith('/program-flow'))
        (jsonDecode(r.body) as Map)['items'] as List<Object?>,
  ];

  const opening = SapProgramFlowItem(
    start: SapTime(8, 0),
    end: SapTime(9, 0),
    activity: 'Opening',
  );

  test('the programme written before the event reaches the server', () async {
    final form = SapForm(service: server());
    await form.load();
    form.updateDetails((d) => d.copyWith(title: 'Written first'));
    form.setProgramFlow(const [opening]);

    await form.bindEvent('e1');

    expect(programmesSent(), isNotEmpty, reason: 'it was never sent');
    expect(programmesSent().last, hasLength(1));
    expect(form.programFlow, hasLength(1));
  });

  testWidgets('saving Part 1 sends its programme too', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final form = SapForm(eventId: 'e1', service: server());
    await form.load();
    // What Save asks for before it sends anything.
    form.updateDetails(
      (d) => d.copyWith(
        setting: SapSetting.onCampus,
        departmentType: 'College',
        department: 'CITE',
      ),
    );
    form.setProgramFlow(const [opening]);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SapPart1Screen(form: form),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BrutButton, 'Save'));
    await tester.pumpAndSettle();

    expect(programmesSent(), isNotEmpty, reason: 'it was never sent');
    expect(programmesSent().last, hasLength(1));
    expect(form.programFlow, hasLength(1));
  });
}
