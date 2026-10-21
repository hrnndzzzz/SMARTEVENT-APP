import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/api_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiConfig.resetForTest();
  });

  group('the committed fallback', () {
    // A LAN address was committed here once. It worked on one laptop on
    // one network and silently hung for everyone else, including in the
    // test suite: an upload test sat for twenty seconds trying to reach
    // it before failing.
    test('is loopback, not somebody\'s machine', () {
      final fallback = ApiConfig.defaultBaseUrl;

      expect(
        fallback,
        anyOf(contains('127.0.0.1'), contains('localhost')),
        reason:
            'the default in the repository has to work on every machine; '
            'point a build elsewhere with --dart-define instead',
      );
    });

    test('and is not what a release should ship with', () {
      // False here means the build fell back, which is never right for
      // a release and is what the backend-address card warns about.
      expect(ApiConfig.isConfigured, isFalse);
    });
  });

  group('normalise', () {
    test('adds http to a bare host and port', () {
      // What anyone reads off a terminal, typed straight in.
      expect(ApiConfig.normalise('192.168.1.5:8000'), 'http://192.168.1.5:8000');
    });

    test('keeps a scheme that was typed', () {
      expect(
        ApiConfig.normalise('https://api.example.org'),
        'https://api.example.org',
      );
    });

    test('strips trailing slashes so paths do not double up', () {
      expect(ApiConfig.normalise('http://10.0.0.2:8000//'), 'http://10.0.0.2:8000');
    });

    test('trims surrounding space', () {
      expect(ApiConfig.normalise('  10.0.0.2:8000 '), 'http://10.0.0.2:8000');
    });

    test('empty stays empty rather than becoming a bare scheme', () {
      expect(ApiConfig.normalise('   '), '');
    });
  });

  group('override', () {
    test('baseUrl follows what was set', () async {
      await ApiConfig.setOverride('10.52.132.218:8001');
      expect(ApiConfig.baseUrl, 'http://10.52.132.218:8001');
      expect(ApiConfig.hasOverride, isTrue);
    });

    test('clearing goes back to the build address', () async {
      await ApiConfig.setOverride('10.0.0.9:9000');
      await ApiConfig.clearOverride();
      expect(ApiConfig.baseUrl, ApiConfig.defaultBaseUrl);
      expect(ApiConfig.hasOverride, isFalse);
    });

    test('survives a restart', () async {
      await ApiConfig.setOverride('10.0.0.4:8000');
      ApiConfig.resetForTest();
      expect(ApiConfig.hasOverride, isFalse, reason: 'reset clears memory');

      await ApiConfig.load();
      expect(ApiConfig.baseUrl, 'http://10.0.0.4:8000');
    });

    test('an empty address is refused', () {
      expect(
        () => ApiConfig.setOverride('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('an address with no host is refused', () {
      expect(
        () => ApiConfig.setOverride('http://'),
        throwsA(isA<FormatException>()),
      );
    });

    test('load with nothing stored leaves the build address alone', () async {
      await ApiConfig.load();
      expect(ApiConfig.hasOverride, isFalse);
      expect(ApiConfig.baseUrl, ApiConfig.defaultBaseUrl);
    });
  });
}
