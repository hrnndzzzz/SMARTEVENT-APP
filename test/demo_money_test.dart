import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/income.dart';
import 'package:smartevent/api/models/receipt.dart';
import 'package:smartevent/api/models/remote_expense.dart';
import 'package:smartevent/state/app_state.dart';

/// The money half of the demo.
///
/// Each of these went straight to the server, so in demo mode the button
/// was there and the press was refused with "nothing is sent to a
/// server". The financial controls are the part a panel is most likely
/// to ask to see, so they have to work without a backend.
///
/// Every test asserts the demo *answers* rather than refuses, because a
/// branch that never runs analyzes perfectly well and fails only here.
void main() {
  AppState treasurer() => AppState()..enterDemo(role: UserRole.treasurer);

  ExpenseEntry pendingExpense(AppState app) =>
      app.expenses.firstWhere((e) => e.status == ExpenseStatus.pending);

  // ---- Income ------------------------------------------------------------

  group('income', () {
    test('the ledger is answered from the seed rather than left empty', () async {
      final app = treasurer();

      await app.loadIncomes();

      expect(app.incomes, isNotEmpty, reason: 'the demo must not refuse this');
      expect(app.incomesLoad.hasFailed, isFalse);
    });

    test('a withheld row is listed but kept out of the counted total', () async {
      final app = treasurer();
      await app.loadIncomes();

      final withheld = app.incomes.where((i) => i.isWithheld);

      expect(withheld, isNotEmpty, reason: 'the rule is invisible without one');
      expect(app.withheldIncomeTotal, greaterThan(0));
      expect(
        app.countedIncomeTotal,
        isNot(contains(withheld.first.amount)),
        reason: 'a withheld amount must not reach the counted total',
      );
      expect(
        app.countedIncomeTotal + app.withheldIncomeTotal,
        closeTo(app.incomes.fold(0.0, (sum, i) => sum + i.amount), 0.001),
        reason: 'counted and withheld must account for every row',
      );
    });

    test('recording income adds it to the ledger', () async {
      final app = treasurer();
      await app.loadIncomes();
      final before = app.incomes.length;

      final error = await app.recordIncome(
        eventId: 'demo-ev-1',
        source: 'Canteen concessionaire',
        sourceType: FundSource.other,
        purpose: 'Booth rental',
        amount: '900',
        receivedOn: DateTime(2026, 11, 6),
      );

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(app.incomes.length, before + 1);
      expect(app.incomes.first.source, 'Canteen concessionaire');
      expect(app.incomes.first.amount, 900);
    });

    test('income recorded with a receipt is withheld until reviewed', () async {
      final app = treasurer();
      await app.loadIncomes();

      await app.recordIncome(
        eventId: 'demo-ev-1',
        source: 'Raffle proceeds',
        sourceType: FundSource.other,
        purpose: 'Prizes',
        amount: '500',
        receipt: ReceiptDetailsInput(
          receiptUrl: 'demo://receipts/raffle.jpg',
          purpose: 'Prizes',
        ),
      );

      expect(app.incomes.first.isWithheld, isTrue);
      expect(
        app.incomes.first.receiptReviewStatus,
        ReceiptReviewStatus.pending,
      );
    });

    test('a recorded row survives the event filter', () async {
      final app = treasurer();
      await app.loadIncomes();

      await app.recordIncome(
        eventId: 'demo-ev-1',
        source: 'Canteen concessionaire',
        sourceType: FundSource.other,
        purpose: 'Booth rental',
        amount: '900',
      );
      await app.applyIncomeFilter(eventId: 'demo-ev-1');

      expect(
        app.incomes.where((i) => i.source == 'Canteen concessionaire'),
        hasLength(1),
        reason: 'rebuilding from the seed would drop what was just recorded',
      );
    });
  });

  // ---- Approving and rejecting -------------------------------------------

  group('expense review', () {
    test('approving a pending expense records the decision', () async {
      final app = treasurer();
      final expense = pendingExpense(app);

      final error = await app.approveExpense(expense, reviewerRole: 'Treasurer');

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(expense.status, ExpenseStatus.approved);
      expect(expense.reviewedBy, 'Treasurer');
    });

    test('rejecting keeps the reviewer note', () async {
      final app = treasurer();
      final expense = pendingExpense(app);

      final error = await app.rejectExpense(
        expense,
        reviewerRole: 'Treasurer',
        note: 'No quotation attached.',
      );

      expect(error, isNull);
      expect(expense.status, ExpenseStatus.rejected);
      expect(expense.reviewNote, 'No quotation attached.');
    });

    test('an empty note is not stored as an empty string', () async {
      final app = treasurer();
      final expense = pendingExpense(app);

      await app.approveExpense(expense, reviewerRole: 'Treasurer', note: '');

      expect(expense.reviewNote, isNull);
    });

    test('the same expense cannot be decided twice', () async {
      final app = treasurer();
      final expense = pendingExpense(app);
      await app.approveExpense(expense, reviewerRole: 'Treasurer');

      final second = await app.rejectExpense(expense, reviewerRole: 'Admin');

      expect(second, isNotNull, reason: 'the backend refuses this too');
      expect(
        expense.status,
        ExpenseStatus.approved,
        reason: 'the refused decision must not have changed anything',
      );
    });
  });

  // ---- Scanning a receipt -------------------------------------------------

  group('receipt scanning', () {
    test('a scan is answered rather than refused', () async {
      final app = treasurer();

      final outcome = await app.scanReceipt(bytes: const [1, 2, 3], filename: 'r.jpg');

      expect(outcome.error, isNull, reason: 'the demo must not refuse this');
      expect(outcome.scan, isNotNull);
      expect(outcome.scan!.merchant, isNotNull);
      expect(outcome.scan!.items, isNotEmpty);
    });

    test('the scanned lines reconcile to the scanned total', () async {
      final app = treasurer();

      final scan = (await app.scanReceipt(bytes: const [1], filename: 'r.jpg')).scan!;

      expect(
        scan.items.fold(0.0, (sum, line) => sum + line.amount),
        closeTo(scan.amount!, 0.001),
        reason: 'a scan whose lines do not add up is what the parser refuses',
      );
    });

    test('saving the scanned expense adds it as pending', () async {
      final app = treasurer();
      final before = app.expenses.length;

      final result = await app.createExpense(
        categoryId: app.categories.first.id,
        description: 'LCUP Campus Store',
        amount: '1220',
      );

      expect(result.error, isNull, reason: 'the demo must not refuse this');
      expect(app.expenses.length, before + 1);
      expect(app.expenses.first.status, ExpenseStatus.pending);
      expect(app.expenses.first.category, app.categories.first.name);
    });
  });

  // ---- Purchase completion into stock -------------------------------------

  group('completing a purchase', () {
    ExpenseEntry assetExpense(AppState app) =>
        app.expenses.firstWhere((e) => e.remoteId == 'demo-ex-2');

    PurchaseCompletionInput completionFor(List<ExpenseLine> assets) =>
        PurchaseCompletionInput(
          paidOn: DateTime(2026, 11, 1),
          receivedOn: DateTime(2026, 11, 2),
          paidAmount: '1850',
          paymentMethod: PaymentMethod.cash,
          paymentReference: 'OR-5512',
          vendor: 'National Book Store',
          items: [
            for (final line in assets)
              PurchaseLineConfirmation(
                expenseItemId: line.id,
                quantity: line.quantity,
                unit: line.unit,
              ),
          ],
        );

    test('an approved expense has asset lines to confirm', () async {
      final app = treasurer();

      final outcome = await app.loadExpenseLines(assetExpense(app));

      expect(outcome.error, isNull, reason: 'the demo must not refuse this');
      expect(outcome.lines, isNotEmpty);
      expect(outcome.lines!.where((l) => l.isAsset), isNotEmpty);
    });

    // The method working is worth nothing if the button never appears.
    // This is the exact condition expense_detail_screen gates it on.
    test('the Complete purchase button is actually offered', () async {
      final app = treasurer();
      final expense = assetExpense(app);
      final lines = (await app.loadExpenseLines(expense)).lines!;

      expect(app.isOfflineViewing, isFalse);
      expect(expense.canStartPurchaseCompletion, isTrue);
      expect(app.mayRecordFinance, isTrue);
      expect(lines.where((l) => l.isAsset), isNotEmpty);
    });

    test('completing it turns each asset line into stock', () async {
      final app = treasurer();
      final expense = assetExpense(app);
      final assets =
          (await app.loadExpenseLines(expense)).lines!.where((l) => l.isAsset).toList();
      await app.loadCatalog();
      final before = app.catalog.length;

      final error = await app.completePurchase(expense, completionFor(assets));

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(app.catalog.length, before + assets.length);
      for (final line in assets) {
        final item = app.catalog.firstWhere((i) => i.itemName == line.name);
        expect(item.quantity, line.quantity);
      }
    });

    test('the arrival is recorded as a movement, not written onto the row', () async {
      final app = treasurer();
      final expense = assetExpense(app);
      final assets =
          (await app.loadExpenseLines(expense)).lines!.where((l) => l.isAsset).toList();
      await app.completePurchase(expense, completionFor(assets));

      final item = app.catalog.firstWhere((i) => i.itemName == assets.first.name);
      final ledger = await app.loadMovements(item);

      expect(ledger.movements, isNotEmpty);
      expect(ledger.movements!.first.type, InventoryMovementType.purchase);
      expect(
        ledger.movements!.fold(0, (sum, m) => sum + m.changeQty),
        item.quantity,
        reason: 'the ledger must account for every unit on the row',
      );
    });

    // Caught on the phone, not here: the stock was added correctly but the
    // button stayed, and the refusal only arrived after the whole form had
    // been filled in a second time.
    test('the button stops being offered once it is done', () async {
      final app = treasurer();
      final expense = assetExpense(app);
      final assets =
          (await app.loadExpenseLines(expense)).lines!.where((l) => l.isAsset).toList();
      expect(expense.canStartPurchaseCompletion, isTrue);

      await app.completePurchase(expense, completionFor(assets));

      expect(expense.isPurchaseCompleted, isTrue);
      expect(
        expense.canStartPurchaseCompletion,
        isFalse,
        reason: 'the Complete purchase button must be gone',
      );
    });

    test('stock is never added twice', () async {
      final app = treasurer();
      final expense = assetExpense(app);
      final assets =
          (await app.loadExpenseLines(expense)).lines!.where((l) => l.isAsset).toList();
      await app.completePurchase(expense, completionFor(assets));
      await app.loadCatalog();
      final after = app.catalog.length;

      final second = await app.completePurchase(expense, completionFor(assets));

      expect(second, contains('already completed'));
      expect(app.catalog.length, after, reason: 'nothing may have been added');
    });

    test('an unapproved expense cannot be completed', () async {
      final app = treasurer();
      final expense = pendingExpense(app);

      final error = await app.completePurchase(
        expense,
        completionFor(const []),
      );

      expect(error, contains('approved'));
    });
  });
}
