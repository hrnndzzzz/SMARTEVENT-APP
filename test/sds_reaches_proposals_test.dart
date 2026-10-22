import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/proposal_letters_screen.dart';
import 'package:smartevent/screens/sds_proposals_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_theme.dart';

/// SDS owns Part 4, the paper checkpoints, the return, the final scan and
/// Part 6. Every one of those is reached through an event, and the role
/// is otherwise held to proposal letters — so the office had work it
/// could not open.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(AppState app, Widget child) => ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );

  testWidgets('the letters screen offers SDS a way to the proposals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    final app = AppState()..enterDemo(role: UserRole.sdsStaff);

    await tester.pumpWidget(host(app, const ProposalLettersScreen()));
    // A spinner runs while the (empty) letter list loads, and a
    // spinner never settles.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Proposals'), findsOneWidget);
  });

  testWidgets('and nobody else sees it there', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    await tester.pumpWidget(host(app, const ProposalLettersScreen()));
    // A spinner runs while the (empty) letter list loads, and a
    // spinner never settles.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Part 4 onwards, and the signing'), findsNothing);
  });

  testWidgets('the list shows what has been submitted', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final app = AppState()..enterDemo(role: UserRole.sdsStaff);

    await tester.pumpWidget(host(app, const SdsProposalsScreen()));
    await tester.pumpAndSettle();

    // The seeded set has events past draft; drafts are nobody's to review.
    expect(find.textContaining('submitted across the school'), findsOneWidget);
    expect(find.byType(Card), findsNothing, reason: 'uses BrutCard');
  });

  test('every stage is said in words, not left to the enum', () {
    for (final status in EventApprovalStatus.values) {
      final (label, _) = SdsProposalsScreen.stageOf(status);
      expect(label.trim(), isNotEmpty, reason: status.name);
    }

    expect(
      SdsProposalsScreen.stageOf(EventApprovalStatus.pendingAdviser).$1,
      'With the moderator',
    );
  });
}
