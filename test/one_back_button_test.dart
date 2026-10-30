import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part2_screen.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/screens/sap/sap_part4_screen.dart';
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/screens/sap/sap_part6_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// F7: two back buttons, one in the header and one in the footer, doing
/// the same thing. Parts 1 to 3 and 5 had already been reduced to one;
/// Parts 4 and 6 still carried both.
///
/// The convention is the header's, so these count what renders rather
/// than what is written: Parts 1 to 3 declare two headers and show one,
/// depending on whether the part is opened on its own or as a step.
void main() {
  Widget host(Widget screen) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(theme: AppTheme.light(), home: screen),
  );

  SapForm form() => SapForm(eventId: 'e1');

  final screens = <String, Widget Function()>{
    'Part 1': () => SapPart1Screen(form: form()),
    'Part 2': () => SapPart2Screen(form: form()),
    'Part 3': () => SapPart3Screen(form: form()),
    'Part 4': () => SapPart4Screen(form: form()),
    'Part 5': () => SapPart5Screen(form: form()),
    'Part 6': () => SapPart6Screen(form: form()),
  };

  screens.forEach((name, build) {
    testWidgets('$name offers one way back', (tester) async {
      tester.view.devicePixelRatio = 2.75;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(build()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.bySemanticsLabel('Back'),
        findsOneWidget,
        reason: '$name should have exactly one back button',
      );
    });
  });
}
