import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Supporting files are listed on the proposal hub. Every one of them
/// read "Open supporting file", so three attachments gave three
/// identical buttons and no way to tell the ROC/COC — the one with a
/// rule attached — from an appendix.
void main() {
  testWidgets('each attachment names what it is', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2600);
    addTearDown(tester.view.reset);

    final client = MockClient((request) async {
      final body = request.url.path.endsWith('/attachments')
          ? [
              {
                'id': 'a1',
                'category': 'roc_coc',
                'filename': 'roc-signed.pdf',
                'size_bytes': 12345,
                'revision_no': 1,
              },
              {
                'id': 'a2',
                'category': 'appendix',
                'filename': 'venue-map.pdf',
                'size_bytes': 999,
                'revision_no': 1,
              },
            ]
          : {'detail': 'Not Found'};
      return http.Response(
        jsonEncode(body),
        request.url.path.endsWith('/attachments') ? 200 : 404,
        headers: {'content-type': 'application/json'},
      );
    });

    final form = SapForm(
      eventId: 'e1',
      service: SapService(ApiClient(httpClient: client)),
    );
    await form.loadAttachments();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SapFormScreen(form: form),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ROC / COC'), findsOneWidget);
    expect(find.text('Appendix'), findsOneWidget);
    expect(find.text('ROC-SIGNED.PDF'), findsOneWidget);
    expect(
      find.text('Open supporting file'),
      findsNothing,
      reason: 'the same label on every row names none of them',
    );
  });
}
