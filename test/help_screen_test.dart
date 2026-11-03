import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/help_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The help describes the screens as they are. A rejection by the SDS
/// Office is final now, and the help still told people to edit the event
/// and resubmit it from a button that is no longer there.
void main() {
  testWidgets('a rejection is final, and the help says where to read why', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(theme: AppTheme.light(), home: const HelpScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('It was rejected. Can I fix it?'));
    await tester.pump();

    expect(find.textContaining('SDS Office is final'), findsOneWidget);
    expect(find.textContaining('Proposal form'), findsOneWidget);
    expect(find.textContaining('start a new proposal'), findsOneWidget);
    expect(find.textContaining('Edit proposal'), findsNothing);
    expect(find.textContaining('Resubmitting'), findsNothing);
  });

  // A proposal goes to the Moderator, then the Dean, then the SDS Office. The
  // help still taught two stages with an Admin's final sign-off, where either
  // could reject it.
  testWidgets('approval goes Moderator, Dean, then the SDS Office', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(theme: AppTheme.light(), home: const HelpScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Who approves it, and in what order?'));
    await tester.pump();

    expect(find.textContaining('Moderator'), findsOneWidget);
    expect(find.textContaining('Dean'), findsOneWidget);
    expect(find.textContaining('SDS Office'), findsOneWidget);
    expect(
      find.textContaining('only the SDS Office can reject it'),
      findsOneWidget,
    );
    // The self-approval rule is still true, and still said.
    expect(
      find.textContaining('Nobody can approve a proposal they wrote'),
      findsOneWidget,
    );
    expect(find.textContaining('final sign-off'), findsNothing);
    expect(find.textContaining('reject it with a remark'), findsNothing);
  });
}
