import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/signature_pad.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Drawing and scrolling are one finger going one way.
///
/// Reported from both ends on the same evening: the page scrolled
/// instead of signing, and scrolling past the pad left a mark on it —
/// a mark which is enough to enable "Approve and sign" on an
/// institutional form.
///
/// One cause. The pad used to override `rejectGesture` to accept, but
/// `rejectGesture` runs *after* the scrollable has already won the
/// arena, so accepting there added the pad as a second handler of the
/// same touch. The page scrolled and the pad drew, at once.
void main() {
  late SapSignature? drawn;
  late ScrollController scroll;

  Future<void> open(WidgetTester tester) async {
    drawn = null;
    scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.binding.setSurfaceSize(const Size(420, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                // Enough above and below that the page genuinely can
                // scroll, which is the whole contest.
                const SizedBox(height: 500),
                SapSignaturePad(onChanged: (s) => drawn = s),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(420);
    await tester.pumpAndSettle();
  }

  testWidgets('a stroke on the pad draws, and does not scroll the page', (
    tester,
  ) async {
    await open(tester);
    final before = scroll.offset;
    final pad = tester.getCenter(find.byType(SapSignaturePad));

    // Straight down the middle: the stem of a letter, and the exact
    // gesture a scrollable claims.
    await tester.dragFrom(pad, const Offset(0, 60));
    await tester.pumpAndSettle();

    expect(drawn?.strokes, isNotEmpty, reason: 'the signature was never drawn');
    expect(
      scroll.offset,
      before,
      reason: 'the page scrolled out from under the signature',
    );
  });

  testWidgets('and the page still scrolls from beside the pad', (tester) async {
    // The pad takes what starts on it and nothing else — otherwise a
    // page carrying one could never be read.
    await open(tester);
    final before = scroll.offset;

    // Well clear of the pad: at this offset the pad's top edge is at
    // y = 80, so anything lower is on the canvas.
    final padTop = tester.getTopLeft(find.byType(SapSignaturePad)).dy;
    await tester.dragFrom(Offset(210, padTop - 40), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(scroll.offset, isNot(before), reason: 'the page is stuck');
    expect(drawn, isNull, reason: 'scrolling above the pad marked it');
  });
}
