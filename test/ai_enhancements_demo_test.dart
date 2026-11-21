import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';

/// The three AI features answer in the demo, which is where a panel sees
/// them: the budget suggestion, the receipt's category, and the reading
/// of the financial report.
void main() {
  AppState treasurer() => AppState()..enterDemo(role: UserRole.treasurer);

  test('the proposal form gets a budget suggestion with what it compared', () async {
    final suggestion = await treasurer().suggestBudget(title: 'Science Fair');

    expect(suggestion?.amount, greaterThan(0));
    expect(suggestion?.similarTitles, isNotEmpty);
  });

  test('a scanned receipt suggests one of the categories on offer', () async {
    final app = treasurer();
    final scan = (await app.scanReceipt(bytes: [1], filename: 'r.jpg')).scan;

    expect(
      app.categories.map((c) => c.id),
      contains(scan?.suggestedCategoryId),
    );
  });

  test('the financial report comes with an AI analysis', () async {
    final app = treasurer();
    await app.loadFinancialReport();

    expect(app.financialReading?.headline, isNotNull);
    expect(app.financialReading?.happened, isNotEmpty);
    expect(app.financialReading?.outlook, isNotEmpty);
    expect(app.financialReading?.actions, isNotEmpty);
  });
}
