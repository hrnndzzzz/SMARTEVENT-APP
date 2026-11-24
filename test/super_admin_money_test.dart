import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/expense_service.dart';
import 'package:smartevent/api/income_service.dart';
import 'package:smartevent/api/models/income.dart';
import 'package:smartevent/screens/income_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// A Super Admin belongs to no organization, so the server refuses its
/// general-fund income and its receipt scans unless it names one.
void main() {
  test('general-fund income names the organization it is for', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 'income-1',
          'school_year': '2026-2027',
          'semester': 'first',
          'source': 'Members',
          'source_type': 'membership_dues',
          'purpose': 'Dues',
          'amount': 100,
          'received_on': '2026-11-22',
          'recorded_by': 'admin-1',
          'created_at': '2026-11-22T00:00:00Z',
        }),
        201,
      );
    });

    await IncomeService(ApiClient(httpClient: client)).record(
      eventId: null,
      source: 'Members',
      sourceType: FundSource.membershipDues,
      purpose: 'Dues',
      amount: '100.00',
      schoolYear: '2026-2027',
      semester: 'first',
      organizationId: 'org-1',
    );

    expect(sent?['organization_id'], 'org-1');
  });

  test('a receipt scan names the organization it is filed under', () async {
    String? body;
    final client = MockClient((request) async {
      body = utf8.decode(request.bodyBytes, allowMalformed: true);
      return http.Response(jsonEncode({'receipt_url': 'https://x/r.jpg'}), 200);
    });

    await ExpenseService(
      ApiClient(httpClient: client),
    ).scanReceipt(bytes: [1, 2, 3], filename: 'r.jpg', organizationId: 'org-1');

    expect(body, contains('name="organization_id"'));
    expect(body, contains('org-1'));
  });

  Future<AppState> openIncomeForm(WidgetTester tester, UserRole role) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: role);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const IncomeScreen()),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await settle();
    await tester.tap(find.byType(FloatingActionButton));
    await settle();
    await tester.tap(find.text('Select an event or the general fund'));
    await settle();
    await tester.tap(find.text('General fund (no event)').last);
    await settle();
    await tester.tap(find.text('Select a semester'));
    await settle();
    await tester.tap(find.text('First semester').last);
    await settle();
    return app;
  }

  testWidgets('a Super Admin chooses whose general fund it is', (tester) async {
    final app = await openIncomeForm(tester, UserRole.superAdmin);
    expect(find.text('ORGANIZATION'), findsOneWidget);

    final before = app.incomes.length;
    await tester.ensureVisible(find.text('Record income').last);
    await tester.tap(find.text('Record income').last);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Choose the organization'), findsOneWidget);
    expect(app.incomes.length, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Treasurer is not asked, it has its own', (tester) async {
    await openIncomeForm(tester, UserRole.officer);
    expect(find.text('ORGANIZATION'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
