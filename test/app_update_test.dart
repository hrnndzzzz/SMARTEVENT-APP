import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/state/app_update.dart';

void main() {
  test('the tag comes from the latest-release redirect', () {
    expect(
      AppUpdate.tagFromLocation(
        'https://github.com/hrnndzzzz/SMARTEVENT-APP/releases/tag/v1.0.4',
      ),
      'v1.0.4',
    );
    expect(AppUpdate.tagFromLocation(null), isNull);
    expect(AppUpdate.tagFromLocation('https://github.com/login'), isNull);
  });

  test('only a later version counts as newer', () {
    expect(AppUpdate.isNewer('v1.0.4', 'v1.0.3'), isTrue);
    expect(AppUpdate.isNewer('v1.0.10', 'v1.0.9'), isTrue, reason: 'numbers');
    expect(AppUpdate.isNewer('v2.0.0', 'v1.9.9'), isTrue);
    expect(AppUpdate.isNewer('v1.0.3', 'v1.0.3'), isFalse);
    expect(AppUpdate.isNewer('v1.0.2', 'v1.0.3'), isFalse);
    // A mistyped tag must never lock the app behind an endless update.
    expect(AppUpdate.isNewer('v1.0.4', 'release-4'), isFalse);
    expect(AppUpdate.isNewer('latest', 'v1.0.3'), isFalse);
  });

  MockClient redirectTo(String tag) => MockClient(
    (_) async => http.Response(
      '',
      302,
      headers: {
        'location':
            'https://github.com/hrnndzzzz/SMARTEVENT-APP/releases/tag/$tag',
      },
    ),
  );

  test('an older build is offered the latest release', () async {
    expect(
      await AppUpdate.newerRelease(
        current: 'v1.0.3',
        client: redirectTo('v1.0.4'),
      ),
      'v1.0.4',
    );
    expect(
      await AppUpdate.newerRelease(
        current: 'v1.0.4',
        client: redirectTo('v1.0.4'),
      ),
      isNull,
    );
  });

  test('a dev build and an unreachable GitHub never block the app', () async {
    expect(
      await AppUpdate.newerRelease(current: '', client: redirectTo('v9.0.0')),
      isNull,
    );
    expect(
      await AppUpdate.newerRelease(
        current: 'v1.0.3',
        client: MockClient((_) async => throw http.ClientException('down')),
      ),
      isNull,
    );
  });

  group('the manual check keeps the answers apart', () {
    // newerRelease returns null for three different situations, which
    // is right at launch and wrong behind a button: "up to date" is the
    // one answer a person acts on by not looking again, so it must
    // never be what they are told after a failed request.
    test('a later release comes back as available, with its tag', () async {
      final found = await AppUpdate.check(
        current: 'v1.0.3',
        client: redirectTo('v1.0.4'),
      );

      expect(found.state, UpdateCheck.available);
      expect(found.tag, 'v1.0.4');
    });

    test('the same release comes back as up to date', () async {
      final found = await AppUpdate.check(
        current: 'v1.0.4',
        client: redirectTo('v1.0.4'),
      );

      expect(found.state, UpdateCheck.upToDate);
      expect(found.tag, 'v1.0.4', reason: 'so the screen can name it');
    });

    test('a newer phone than GitHub is still up to date, not stale', () async {
      final found = await AppUpdate.check(
        current: 'v1.1.0',
        client: redirectTo('v1.0.4'),
      );

      expect(found.state, UpdateCheck.upToDate);
    });

    test('an unreachable GitHub is never reported as up to date', () async {
      final found = await AppUpdate.check(
        current: 'v1.0.3',
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(found.state, UpdateCheck.unreachable);
      expect(found.tag, isNull);
    });

    test(
      'a redirect to something that is not a release is unreachable',
      () async {
        final found = await AppUpdate.check(
          current: 'v1.0.3',
          client: MockClient(
            (_) async => http.Response(
              '',
              302,
              headers: {'location': 'https://github.com/login'},
            ),
          ),
        );

        expect(
          found.state,
          UpdateCheck.unreachable,
          reason: 'an answer nobody could read is not an answer',
        );
      },
    );

    test('a build with no tag says so rather than claiming either', () async {
      final found = await AppUpdate.check(
        current: '',
        client: redirectTo('v9.0.0'),
      );

      expect(found.state, UpdateCheck.untagged);
    });

    test('newerRelease still collapses everything but available', () async {
      expect(
        await AppUpdate.newerRelease(
          current: 'v1.0.4',
          client: redirectTo('v1.0.4'),
        ),
        isNull,
      );
      expect(
        await AppUpdate.newerRelease(
          current: 'v1.0.3',
          client: redirectTo('v1.0.4'),
        ),
        'v1.0.4',
      );
    });
  });
}
