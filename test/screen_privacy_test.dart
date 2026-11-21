import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/state/screen_privacy.dart';

/// Keeping the screens that carry other people's details out of
/// screenshots and recordings.
///
/// Android's FLAG_SECURE is a property of the window and Flutter has
/// one window, so it is on for the whole app or off for all of it.
/// That is the whole difficulty: screens stack, and clearing the flag
/// when one closes would unprotect another still underneath.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<bool> sent;

  setUp(() {
    sent = [];
    ScreenPrivacy.reset();
    ScreenPrivacy.exempt = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenPrivacy.channel, (call) async {
          if (call.method == 'set') sent.add(call.arguments as bool);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenPrivacy.channel, null);
    ScreenPrivacy.reset();
    ScreenPrivacy.exempt = false;
  });

  // The platform call only goes out on Android; everywhere else the
  // flag does not exist. Tests run on the host, so assert the counter
  // and check the calls only where they are made.
  final onAndroid = ScreenPrivacy.supported;

  test('the first claim turns it on, the rest do not repeat it', () async {
    await ScreenPrivacy.claim();
    await ScreenPrivacy.claim();
    await ScreenPrivacy.claim();

    expect(ScreenPrivacy.claims, 3);
    if (onAndroid) expect(sent, [true]);
  });

  test('it stays on until the last screen lets go', () async {
    await ScreenPrivacy.claim();
    await ScreenPrivacy.claim();

    await ScreenPrivacy.release();
    expect(ScreenPrivacy.claims, 1);
    // One of two guarded screens closing must not unprotect the one
    // still underneath it.
    if (onAndroid) expect(sent, [true]);

    await ScreenPrivacy.release();
    expect(ScreenPrivacy.claims, 0);
    if (onAndroid) expect(sent, [true, false]);
  });

  test('releasing more than was claimed cannot go negative', () async {
    await ScreenPrivacy.release();
    await ScreenPrivacy.release();
    expect(ScreenPrivacy.claims, 0);

    // A stray release must not leave the counter below zero, where the
    // next real claim would fail to turn the flag on.
    await ScreenPrivacy.claim();
    expect(ScreenPrivacy.claims, 1);
    if (onAndroid) expect(sent, [true]);
  });

  test('the demo is exempt, and claims nothing', () async {
    // FLAG_SECURE blocks screen recording too, and the defence demo is
    // recorded on seeded records that belong to nobody.
    ScreenPrivacy.exempt = true;

    await ScreenPrivacy.claim();
    await ScreenPrivacy.claim();

    expect(ScreenPrivacy.claims, 0);
    expect(sent, isEmpty);
  });

  testWidgets('a guarded screen claims while it is up', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PrivateScreen(child: SizedBox()),
      ),
    );
    expect(ScreenPrivacy.claims, 1);

    // Replaced by something unguarded: the claim goes with it.
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    expect(ScreenPrivacy.claims, 0);
  });

  testWidgets('two guarded screens at once keep one claim each', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            PrivateScreen(child: SizedBox()),
            PrivateScreen(child: SizedBox()),
          ],
        ),
      ),
    );
    expect(ScreenPrivacy.claims, 2);
  });
}
