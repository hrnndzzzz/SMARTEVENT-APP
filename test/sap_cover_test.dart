import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_cover_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The form opens on its own cover now, not on a field.
///
/// Off campus is asked here because it is not a detail: it brings thirty
/// days' notice, a ROC or COC and the parents' consent with it, and
/// asking at the top means nobody fills in three steps before finding
/// out.
void main() {
  Widget host(SapForm form, {void Function(BuildContext)? onBegin}) =>
      MaterialApp(
        theme: AppTheme.light(),
        home: SapCoverScreen(form: form, onBegin: onBegin ?? (_) {}),
      );

  group('the school year', () {
    test('turns over in June, with the academic year', () {
      expect(SapCoverScreen.schoolYearFor(DateTime(2026, 8, 1)), '2026-2027');
      expect(SapCoverScreen.schoolYearFor(DateTime(2026, 6, 1)), '2026-2027');
    });

    test('and February still belongs to the year before', () {
      expect(SapCoverScreen.schoolYearFor(DateTime(2027, 2, 1)), '2026-2027');
      expect(SapCoverScreen.schoolYearFor(DateTime(2026, 5, 31)), '2025-2026');
    });
  });

  testWidgets('it shows the paper\'s own heading', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('LA CONSOLACION'), findsOneWidget);
    expect(find.textContaining('SAS-SDS-FO-020'), findsOneWidget);
  });

  testWidgets('nothing starts until the setting is chosen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    final button = tester.widget<BrutButton>(
      find.widgetWithText(BrutButton, 'Start the form'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('on campus is enough to start', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    final form = SapForm(eventId: 'e1')
      ..updateDetails((d) => d.copyWith(setting: SapSetting.onCampus));

    await tester.pumpWidget(host(form));
    await tester.pumpAndSettle();

    final button = tester.widget<BrutButton>(
      find.widgetWithText(BrutButton, 'Start the form'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('off campus is not, until it is acknowledged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    final form = SapForm(eventId: 'e1')
      ..updateDetails((d) => d.copyWith(setting: SapSetting.offCampus));

    await tester.pumpWidget(host(form));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thirty days of notice'), findsOneWidget);
    expect(
      tester
          .widget<BrutButton>(find.widgetWithText(BrutButton, 'Start the form'))
          .onPressed,
      isNull,
    );

    form.updateDetails((d) => d.copyWith(offCampusAgreement: true));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<BrutButton>(find.widgetWithText(BrutButton, 'Start the form'))
          .onPressed,
      isNotNull,
    );
  });
}
