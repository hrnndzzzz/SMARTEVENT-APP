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
}
