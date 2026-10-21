import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/api_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiConfig.resetForTest();
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
