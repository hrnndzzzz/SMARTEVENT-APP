import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/theme/app_layout.dart';

/// The SDS screens lay out on the app's scale, not on gaps picked per
/// block.
///
/// Reported from a handset: "the indentation is kinda uneven, idk the
/// sds ui seems unorganized". No single gap was wrong — the summary
/// had 16, 20, 20 and 14 before its four headings and 10, 10, 8, 8
/// under them, and the signing screen had its own set. Four rhythms
/// on two screens is what reads as unorganised.
///
/// This reads the source rather than the rendered tree: the fault was
/// hardcoded numbers, so hardcoded numbers are what it has to catch,
/// and a screenshot would not tell one 16 from one 20.
void main() {
  final sds = [
    'lib/screens/sap/sds_summary_screen.dart',
    'lib/screens/sap/sds_sign_screen.dart',
    'lib/screens/sds_proposals_screen.dart',
  ];

  /// The gaps the scale allows. Anything else is a number somebody
  /// chose for one block.
  final allowed = <double>{
    AppLayout.tight, // 8
    AppLayout.between, // 12
    AppLayout.section, // 20
    4.0, // a caption riding under the line above it
    6.0,
    10.0, // cardGap on a short phone
  };

  for (final path in sds) {
    test('${path.split('/').last} uses the scale', () {
      final source = File(path).readAsStringSync();
      final offenders = <String>[];

      for (final match in RegExp(
        r'SizedBox\(height:\s*([0-9]+(?:\.[0-9]+)?)\)',
      ).allMatches(source)) {
        final value = double.parse(match.group(1)!);
        if (!allowed.contains(value)) offenders.add('${match.group(1)}');
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'gaps off the scale: ${offenders.join(', ')} — use '
            'AppLayout.tight, .between or .section',
      );
    });
  }
}
