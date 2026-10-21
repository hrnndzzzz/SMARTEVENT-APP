import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Off campus was refused by the first backend slice and is taken now.
/// It carries conditions the other two settings do not, and the server
/// rejects the proposal when the acknowledgement and the setting
/// disagree — so the form asks here rather than failing at submission.
Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: child);

SapForm formSet(SapSetting setting, {bool acknowledged = false}) {
  final form = SapForm(eventId: 'e1');
  form.updateDetails(
    (d) => d.copyWith(
      setting: setting,
      offCampusAgreement: acknowledged,
      // Far enough out that the notice rule is not what blocks it.
      proposalDate: DateTime(2026, 1, 1),
      activityDate: DateTime(2026, 6, 1),
    ),
  );
  return form;
}

void main() {
  testWidgets('off campus is offered at all', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: SapForm(eventId: 'e1'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Off campus'), findsOneWidget);
  });

  testWidgets('choosing it spells out what it means', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: formSet(SapSetting.offCampus))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thirty days of notice'), findsOneWidget);
    expect(
      find.textContaining('A signed ROC or COC attached'),
      findsOneWidget,
    );
  });

  testWidgets('and offers somewhere to attach it', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formSet(SapSetting.offCampus))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attach the ROC or COC'), findsOneWidget);
    expect(find.textContaining('PDF, PNG or JPEG'), findsOneWidget);
    expect(find.textContaining('is attached.'), findsNothing);
  });

  testWidgets('on campus is asked for no attachment', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formSet(SapSetting.onCampus))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attach the ROC or COC'), findsNothing);
  });

  testWidgets('it will not go on unacknowledged', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: formSet(SapSetting.offCampus))));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot be sent until'), findsOneWidget);
    final button = tester.widget<BrutButton>(
      find.widgetWithText(BrutButton, 'Save'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('acknowledging it lets the step go on', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formSet(SapSetting.offCampus, acknowledged: true))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot be sent until'), findsNothing);
    final button = tester.widget<BrutButton>(
      find.widgetWithText(BrutButton, 'Save'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the conditions belong to off campus alone', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: formSet(SapSetting.onCampus))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thirty days of notice'), findsNothing);
    expect(find.textContaining('cannot be sent until'), findsNothing);
  });

  test('the acknowledgement rides with the setting on the wire', () {
    const off = SapDetails(
      setting: SapSetting.offCampus,
      offCampusAgreement: true,
    );
    expect(off.toPatchJson()['setting'], 'off_campus');
    expect(off.toPatchJson()['off_campus_agreement'], isTrue);

    // False is sent too: the server compares the pair, and a missing
    // flag reads the same as a disagreeing one.
    const on = SapDetails(setting: SapSetting.onCampus);
    expect(on.toPatchJson()['off_campus_agreement'], isFalse);
  });

  test('a setting read back from the server survives the round trip', () {
    final parsed = SapDetails.fromJson({
      'setting': 'off_campus',
      'off_campus_agreement': true,
    });

    expect(parsed.setting, SapSetting.offCampus);
    expect(parsed.offCampusAgreement, isTrue);
  });
}
