import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part2_screen.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/screens/sap/sap_part4_screen.dart';
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/screens/sap/sap_part6_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// With no service the form is local-only, which is exactly the state the
/// screens have to work in until the backend slice lands.
SapForm blankForm() => SapForm(eventId: 'e1');

Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  testWidgets('the hub lists all six parts', (tester) async {
    await tester.pumpWidget(host(SapFormScreen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.text('Activity Details'), findsOneWidget);
    expect(find.text('School Support'), findsOneWidget);
    expect(find.text('Additional Information'), findsOneWidget);
    expect(find.text('SDS Office Clearance'), findsOneWidget);
    expect(find.text('University Clearance'), findsOneWidget);
    expect(find.text('Evaluation'), findsOneWidget);
  });

  testWidgets('the hub says nothing is saved while the routes are absent', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapFormScreen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.textContaining('stays on this phone'), findsOneWidget);
  });

  testWidgets('Part 1 draws the paper\'s fields', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: blankForm())));
    await tester.pumpAndSettle();

    for (final label in [
      'ACTIVITY TITLE',
      'ORGANIZATION',
      'PROGRAM / COURSE',
      'VENUE',
      'PERSONNEL-IN-CHARGE',
      'ATTIRE',
      'NUMBER OF STUDENTS',
      'RATIONALE',
      'OBJECTIVES',
      'EMERGENCY PLAN',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
    expect(find.text('MODALITY'), findsOneWidget);
    expect(find.text('SETTING'), findsOneWidget);
    expect(find.text('AUGUSTINIAN CORE VALUES'), findsOneWidget);
  });

  testWidgets('Part 1 refuses an end time at or before the start', (
    tester,
  ) async {
    final form = blankForm();
    form.updateDetails(
      (d) => d.copyWith(
        startTime: const SapTime(11, 0),
        endTime: const SapTime(8, 0),
      ),
    );

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('end time has to be after'),
      findsOneWidget,
    );
  });

  testWidgets('Part 1 catches an online setting with a face-to-face modality', (
    tester,
  ) async {
    final form = blankForm();
    form.updateDetails(
      (d) => d.copyWith(
        setting: SapSetting.online,
        modality: SapModality.faceToFace,
      ),
    );

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs the modality to be online'), findsOneWidget);
  });

  testWidgets('Part 1 offers all three of the paper settings', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.text('In campus'), findsOneWidget);
    expect(find.text('Off campus'), findsOneWidget);
    expect(find.text('Online'), findsWidgets);
    // What off campus then requires is in off_campus_test.dart.
    expect(
      find.textContaining('separate CHED compliance workflow'),
      findsNothing,
    );
  });

  testWidgets('Part 2 lists every support type the form has', (tester) async {
    await tester.pumpWidget(host(SapPart2Screen(form: blankForm())));
    await tester.pumpAndSettle();

    for (final type in SapSupportType.values) {
      expect(find.text(type.label), findsOneWidget, reason: type.wireName);
    }
  });

  testWidgets('Part 2 asks for a count once a microphone is ticked', (
    tester,
  ) async {
    final form = blankForm();
    await tester.pumpWidget(host(SapPart2Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('HOW MANY'), findsNothing);

    await tester.ensureVisible(find.text('Microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();

    expect(find.text('HOW MANY'), findsOneWidget);
    expect(form.supportRequests.single.type, SapSupportType.microphone);
  });

  testWidgets('Part 3 totals the budget lines exactly', (tester) async {
    final form = blankForm();
    form.setBudgetItems(const [
      SapBudgetItem(particulars: 'Speaker', amount: '2000.00'),
      SapBudgetItem(particulars: 'Certificates', amount: '300.00'),
      SapBudgetItem(particulars: 'Materials', amount: '200.00'),
    ]);

    await tester.pumpWidget(host(SapPart3Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('₱2500.00'), findsOneWidget);
  });

  testWidgets('Part 3 flags a total that disagrees with Part 1', (
    tester,
  ) async {
    final form = blankForm();
    form.updateDetails((d) => d.copyWith(totalBudget: '2500.00'));
    form.setBudgetItems(const [
      SapBudgetItem(particulars: 'Speaker', amount: '2000.00'),
    ]);

    await tester.pumpWidget(host(SapPart3Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.textContaining('have to match'), findsOneWidget);
  });

  testWidgets('Part 4 demands a reason for every not-applicable', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapPart4Screen(form: blankForm())));
    await tester.pumpAndSettle();

    // Consent, medical and compliance all default to not applicable, so
    // the first unanswered reason is shown straight away.
    expect(find.textContaining('Say why'), findsOneWidget);
  });

  testWidgets('Part 4 will not claim no interruption when Part 3 lists one', (
    tester,
  ) async {
    final form = blankForm();
    form.setAffectedClasses([
      SapAffectedClass(
        yearLevel: 'BSCpE 3',
        subject: 'Data & Digital',
        classDate: DateTime(2026, 10, 28),
        start: const SapTime(7, 0),
        end: const SapTime(12, 0),
        professor: 'Engr. Glazen Perez',
      ),
    ]);

    await tester.pumpWidget(host(SapPart4Screen(form: form)));
    await tester.pumpAndSettle();

    // Order on screen: consent reason, attachments, medical reason,
    // compliance reason, ratio. The screen shows one problem at a time,
    // so each has to be answered before the next is reached.
    for (final (index, text) in const [
      (0, 'Online activity'),
      (1, 'Program flow and budget'),
      (2, 'Online activity'),
      (3, 'No off-campus travel'),
    ]) {
      await tester.enterText(find.byType(TextField).at(index), text);
      await tester.pumpAndSettle();
    }

    expect(
      find.textContaining('cannot be "none"'),
      findsOneWidget,
    );
  });

  testWidgets('Part 5 shows nine slots in the paper\'s order', (tester) async {
    await tester.pumpWidget(host(SapPart5Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(SapPart5Screen.blankSlots.length, 9);
    expect(find.text('Organization President'), findsOneWidget);
    expect(find.text('Organization Moderator'), findsNWidgets(2));
    expect(find.text('University President'), findsOneWidget);
    // BrutListRow renders meta through MonoLabel, which uppercases.
    expect(find.text('PREPARED BY'), findsOneWidget);
    expect(find.text('APPROVED BY'), findsOneWidget);
  });

  testWidgets('Part 5 never calls a checkpoint a signature', (tester) async {
    await tester.pumpWidget(host(SapPart5Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.textContaining('signed on paper'), findsOneWidget);
    expect(find.text('Sign'), findsNothing);
    expect(find.text('Sign now'), findsNothing);
  });

  testWidgets('Part 5 offers no Record button before submission', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapPart5Screen(form: blankForm())));
    await tester.pumpAndSettle();

    // No slots exist on the server until the first submission, so there
    // is nothing to record against.
    expect(find.text('Record'), findsNothing);
    expect(find.textContaining('open once the proposal is submitted'),
        findsOneWidget);
  });

  testWidgets('Part 6 needs both an outcome and remarks', (tester) async {
    await tester.pumpWidget(host(SapPart6Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.text('Conducted'), findsOneWidget);
    expect(find.text('Canceled'), findsOneWidget);
    expect(find.text('REMARKS'), findsOneWidget);
  });

  group('part status', () {
    test('an empty form has nothing complete', () {
      final form = blankForm();
      expect(form.completedParts, 0);
      expect(form.statusOf(SapPart.one), SapPartStatus.empty);
    });

    test('Part 5 stays locked until the proposal is submitted', () {
      expect(blankForm().statusOf(SapPart.five), SapPartStatus.locked);
    });

    test('Part 1 reads as started once anything is filled in', () {
      final form = blankForm();
      form.updateDetails((d) => d.copyWith(title: 'Hack the Future'));
      expect(form.statusOf(SapPart.one), SapPartStatus.partial);
    });

    test('Parts 4 to 6 belong to the SDS Office', () {
      expect(SapPart.one.isSdsOnly, isFalse);
      expect(SapPart.three.isSdsOnly, isFalse);
      expect(SapPart.four.isSdsOnly, isTrue);
      expect(SapPart.five.isSdsOnly, isTrue);
      expect(SapPart.six.isSdsOnly, isTrue);
    });
  });
}
