import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/about_screen.dart';
import 'package:smartevent/state/app_update.dart';
import 'package:smartevent/widgets/brand_mark.dart';

/// The one screen whose job is to say which build this is.
void main() {
  Future<void> show(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: AboutScreen()));

  testWidgets('the version is the build tag, not a typed-in number', (
    tester,
  ) async {
    await show(tester);

    // A test host carries no --dart-define, so it is an untagged build
    // and must say so rather than inventing a number.
    expect(AppUpdate.currentTag, isEmpty);
    // MonoLabel renders its text uppercased.
    expect(find.text('DEVELOPMENT BUILD'), findsOneWidget);
    expect(
      find.textContaining('1.0', findRichText: true),
      findsNothing,
      reason: 'no tag means no number to print',
    );
  });

  test('a tagged build names its tag', () {
    expect(
      AppUpdate.versionLabel('v1.0.7'),
      'Version 1.0.7',
      reason:
          'the label says Version and the screen uppercases it, so a '
          'tag kept whole reads "VERSION V1.0.7"',
    );
    expect(AppUpdate.versionLabel('1.0.7'), 'Version 1.0.7');
    expect(
      AppUpdate.versionLabel(''),
      'Development build',
      reason:
          'the hardcoded "Version 1.0" outlived seven releases, so '
          'this label must come from the build and nowhere else',
    );
  });

  testWidgets('it offers a check for updates', (tester) async {
    await show(tester);

    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('it shows the real mark', (tester) async {
    await show(tester);

    expect(find.byType(BrandMark), findsOneWidget);
  });

  testWidgets('nothing is claimed before anyone asks', (tester) async {
    await show(tester);

    expect(find.textContaining('latest release'), findsNothing);
    expect(find.textContaining('Could not reach'), findsNothing);
  });
}
