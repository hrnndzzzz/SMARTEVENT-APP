import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/sap/proposal_steps.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Leaving a part-filled proposal.
///
/// Each step carried two back buttons, one in the header and one in the
/// footer, doing the same thing and saying nothing about whether the
/// work was kept. There is one now, and it asks.
void main() {
  Future<bool?> leave(
    WidgetTester tester, {
    required Future<bool> Function() save,
    required String tap,
  }) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await LeaveProposal.confirm(context, save: save);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('it offers all three ways out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    LeaveProposal.confirm(context, save: () async => true),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Save as draft'), findsOneWidget);
    expect(find.text('Stay here'), findsOneWidget);
    expect(find.text('Leave without saving'), findsOneWidget);
  });

  testWidgets('staying keeps you where you are, and saves nothing', (
    tester,
  ) async {
    var saved = false;
    final out = await leave(
      tester,
      save: () async {
        saved = true;
        return true;
      },
      tap: 'Stay here',
    );

    expect(out, isFalse);
    expect(saved, isFalse);
  });

  testWidgets('leaving without saving does exactly that', (tester) async {
    var saved = false;
    final out = await leave(
      tester,
      save: () async {
        saved = true;
        return true;
      },
      tap: 'Leave without saving',
    );

    expect(out, isTrue);
    expect(saved, isFalse);
  });

  testWidgets('save as draft saves, then leaves', (tester) async {
    var saved = false;
    final out = await leave(
      tester,
      save: () async {
        saved = true;
        return true;
      },
      tap: 'Save as draft',
    );

    expect(saved, isTrue);
    expect(out, isTrue);
  });

  testWidgets('a draft that will not save keeps you on the screen', (
    tester,
  ) async {
    // Otherwise it drops you out of the form and takes the work with it.
    final out = await leave(
      tester,
      save: () async => false,
      tap: 'Save as draft',
    );

    expect(out, isFalse);
  });
}
