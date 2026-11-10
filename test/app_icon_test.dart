import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_icon.dart';

/// Swapping the launcher icon.
///
/// The interesting part is not the happy path but what happens when the
/// platform says no. An icon is not worth an error dialog, and it is
/// certainly not worth the screen behaving as though the swap worked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('smartevent/icon');
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const icons = AppIcons();

  test('it reads back whichever alias is enabled', () async {
    answer((_) => 'light');

    expect(await icons.current(), AppIcon.light);
    expect(calls.single.method, 'current');
  });

  test('an untouched install reads as navy', () async {
    answer((_) => 'navy');

    expect(await icons.current(), AppIcon.navy);
  });

  test('a name this build does not know falls back to navy', () async {
    answer((_) => 'teal-sparkle');

    expect(
      await icons.current(),
      AppIcon.navy,
      reason: 'an alias added by a later build must not crash an older one',
    );
  });

  test('a platform that refuses to answer falls back to navy', () async {
    answer((_) => throw PlatformException(code: 'nope'));

    expect(await icons.current(), AppIcon.navy);
  });

  test('setting passes the name the manifest knows', () async {
    answer((_) => null);

    expect(await icons.set(AppIcon.light), isTrue);
    expect(calls.single.method, 'set');
    expect(calls.single.arguments, 'light');
  });

  test('a refused swap is false, so the screen can say so', () async {
    answer((_) => throw PlatformException(code: 'icon'));

    expect(
      await icons.set(AppIcon.light),
      isFalse,
      reason: 'reporting success here would leave the picker showing an '
          'icon the phone is not using',
    );
  });

  test('every option names itself and explains itself', () {
    for (final icon in AppIcon.values) {
      expect(icon.label, isNotEmpty);
      expect(icon.explanation, isNotEmpty);
    }
  });
}
