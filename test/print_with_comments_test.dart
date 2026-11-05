import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Print asks which version to print once the SDS Office has left remarks:
/// the form with them as comments beside each part, or the clean form.
void main() {
  const noLongerAvailable =
      'The commented copy of this signed revision is no longer available. '
      'Download it without comments for the signed form.';

  /// A loaded proposal in [state] whose `/pdf` requests land in [pdfRequests].
  /// [pdfStatus] 409 answers the way the server does for a signed revision
  /// whose Part 4 is gone.
  Future<SapForm> loaded(
    List<Uri> pdfRequests, {
    bool remarks = true,
    SapState state = SapState.revisionRequested,
    int pdfStatus = 200,
  }) async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/pdf')) {
          pdfRequests.add(request.url);
          if (pdfStatus == 409) {
            return http.Response(
              jsonEncode({'detail': noLongerAvailable}),
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response.bytes(
            [37, 80, 68, 70],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'p1',
            'event_id': 'e1',
            'state': state.wireName,
            'version': 4,
            'revision_no': 1,
            'details': {'title': 'Hack the Future'},
            if (remarks)
              'sds_review': {
                'section_remarks': {'budget': 'Meals over the allowance'},
              },
            'collections': <String, dynamic>{},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final form = SapForm(eventId: 'e1', service: SapService(client));
    await form.load();
    return form;
  }

  Future<void> open(WidgetTester tester, Widget home) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapPrint(WidgetTester tester) async {
    await tester.tap(find.text('Print or share the form'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('the hub\'s Print', () {
    testWidgets('offers both versions when the office left remarks', (
      tester,
    ) async {
      final requests = <Uri>[];
      await open(tester, SapFormScreen(form: await loaded(requests)));
      await tapPrint(tester);

      expect(find.textContaining('With comments: the form with the SDS '
          'Office\'s remarks beside each part.'), findsOneWidget);
      expect(find.textContaining('Without comments: the clean form, as it '
          'goes to the signatories.'), findsOneWidget);
      expect(requests, isEmpty, reason: 'nothing is fetched before choosing');
    });

    testWidgets('"Print with comments" asks for comments=true', (tester) async {
      final requests = <Uri>[];
      await open(tester, SapFormScreen(form: await loaded(requests)));
      await tapPrint(tester);
      await tester.tap(find.text('Print with comments'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.queryParameters['comments'], 'true');
    });

    testWidgets('"Print without comments" sends no comments flag', (
      tester,
    ) async {
      final requests = <Uri>[];
      await open(tester, SapFormScreen(form: await loaded(requests)));
      await tapPrint(tester);
      await tester.tap(find.text('Print without comments'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.queryParameters.containsKey('comments'), isFalse);
    });

    testWidgets('with no remarks it prints the clean form and asks nothing', (
      tester,
    ) async {
      final requests = <Uri>[];
      await open(
        tester,
        SapFormScreen(form: await loaded(requests, remarks: false)),
      );
      await tapPrint(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('With comments'), findsNothing);
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters.containsKey('comments'), isFalse);
    });

    testWidgets('an overall remark alone is still a comment to offer', (
      tester,
    ) async {
      final form = await loaded([], remarks: false)
        ..overallRemarks = 'Not an organizational activity';
      expect(form.hasSdsRemarks, isTrue);
    });

    testWidgets('says why a signed revision has no commented copy', (
      tester,
    ) async {
      final requests = <Uri>[];
      final form = await loaded(
        requests,
        state: SapState.sdsSigned,
        pdfStatus: 409,
      );
      await open(tester, SapFormScreen(form: form));
      await tapPrint(tester);
      await tester.tap(find.text('Print with comments'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(noLongerAvailable),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('Part 5 prints for the signatories without comments', (
    tester,
  ) async {
    final requests = <Uri>[];
    await open(tester, SapPart5Screen(form: await loaded(requests)));
    await tester.tap(find.text('Print for the signatories'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.queryParameters.containsKey('comments'), isFalse);
  });
}
