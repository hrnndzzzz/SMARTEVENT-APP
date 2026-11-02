import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/proposal_letters_screen.dart';
import 'package:smartevent/screens/sap/sds_summary_screen.dart';
import 'package:smartevent/screens/sds_proposals_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/demo_data.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

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
      'With the Moderator',
    );
  });

  // The Dean decides before the office sees a proposal. The list used to
  // call the Dean's step "With the SDS Office" and the office's own "With
  // the signatories".
  test('the Dean is named apart from the SDS Office', () {
    final dean = SdsProposalsScreen.stageOf(EventApprovalStatus.pendingAdmin);
    final office = SdsProposalsScreen.stageOf(
      EventApprovalStatus.pendingInstitutional,
    );

    expect(dean, ('With the Dean', BrutTone.sun));
    expect(office, ('With the SDS Office', BrutTone.sun));
  });

  test('a rejection is final, so it is not called a return', () {
    final rejected = SdsProposalsScreen.stageOf(EventApprovalStatus.rejected);

    expect(rejected, ('Rejected', BrutTone.coral));
  });

  // The demo's SDS role is offered review and signing, and used to have
  // nothing to do it to: no seeded proposal was with the office.
  testWidgets('the demo has a proposal with the office to review and sign', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final app = AppState()..enterDemo(role: UserRole.sdsStaff);
    final withTheOffice = [
      for (final e in app.events)
        if (e.status == EventApprovalStatus.pendingInstitutional) e,
    ];
    expect(withTheOffice, isNotEmpty, reason: 'nothing in the demo is theirs');
    final event = withTheOffice.first;

    // And it is a proposal, not a title: the office has something to read.
    expect(DemoProposals.detailsFor(event), isNotNull);
    expect(DemoProposals.budgetFor(event), isNotEmpty);
    expect(DemoProposals.supportFor(event), isNotEmpty);

    await tester.pumpWidget(host(app, const SdsProposalsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(event.title));
    await tester.pumpAndSettle();

    expect(find.text('Review and decide'), findsOneWidget);
  });

  testWidgets('and the summary opens where the event has got to', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));

    // No server in the demo, so the event's status is the proposal's whole
    // timeline. A draft is not listed at all.
    for (final (status, state) in [
      (EventApprovalStatus.pendingAdviser, SapState.pendingDepartmentReview),
      (EventApprovalStatus.pendingAdmin, SapState.pendingDepartmentReview),
      (EventApprovalStatus.pendingInstitutional, SapState.pendingReview),
      (EventApprovalStatus.rejected, SapState.rejected),
      (EventApprovalStatus.approved, SapState.approved),
      (EventApprovalStatus.completed, SapState.completed),
    ]) {
      final app = AppState()..enterDemo(role: UserRole.sdsStaff);
      app.events
        ..clear()
        ..add(
          EventItem(
            remoteId: 'e1',
            title: 'Fixture event',
            org: 'ACPES',
            date: '28 Oct 2026',
            budget: '2500',
            status: status,
          ),
        );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            // A fresh navigator each time: the last one has the summary on top.
            key: UniqueKey(),
            theme: AppTheme.light(),
            home: const SdsProposalsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixture event'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SdsSummaryScreen>(find.byType(SdsSummaryScreen))
            .form
            .state,
        state,
        reason: status.name,
      );
    }
  });
}
