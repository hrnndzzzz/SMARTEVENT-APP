import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/auth_service.dart';
import 'package:smartevent/api/models/account_permissions.dart';

/// The app kept its own copy of the backend's policy and the copies
/// drifted: the hierarchy work makes financial recording Treasurer-only,
/// where the app also allowed administrators, and lets an Officer who is
/// President propose events, which the app denied outright.
///
/// So the server is asked. The flags are nullable because a backend that
/// predates them sends neither, and absence has to mean "no opinion" —
/// reading it as "no" would lock the app against the live backend.
void main() {
  group('parsing', () {
    test('a backend that answers both is believed', () {
      final p = AccountPermissions.fromJson(const {
        'role': 'officer',
        'position': 'President',
        'scope': 'assigned organization and department',
        'responsibility': 'Propose events and manage own eligible proposals.',
        'permissions': ['Read operational records, reports, and analytics'],
        'can_propose_events': true,
        'can_record_finance': false,
      });

      expect(p.canProposeEvents, isTrue);
      expect(p.canRecordFinance, isFalse);
      expect(p.position, 'President');
      expect(p.hasCapabilityFlags, isTrue);
    });

    test('a backend without the flags says nothing, rather than no', () {
      final p = AccountPermissions.fromJson(const {
        'role': 'admin',
        'scope': 'assigned organization and department',
        'permissions': ['Manage events, expenses, income'],
      });

      expect(p.canProposeEvents, isNull);
      expect(p.canRecordFinance, isNull);
      expect(
        p.hasCapabilityFlags,
        isFalse,
        reason: 'the caller must fall back to the role here',
      );
    });

    test('a non-boolean flag is treated as no opinion', () {
      // Guessing which way a changed contract meant would be worse than
      // falling back to the role the app already shipped with.
      final p = AccountPermissions.fromJson(const {
        'role': 'treasurer',
        'can_record_finance': 'yes',
      });

      expect(p.canRecordFinance, isNull);
    });

    test('a false flag is an answer, not an absence', () {
      final p = AccountPermissions.fromJson(const {
        'role': 'admin',
        'can_record_finance': false,
      });

      expect(p.canRecordFinance, isFalse);
      expect(p.hasCapabilityFlags, isTrue);
    });
  });

  group('over the wire', () {
    late List<http.Request> sent;

    AuthService serviceReturning(Object body, {int status = 200}) {
      sent = [];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      });
      return AuthService(ApiClient(httpClient: client));
    }

    test('it asks /auth/permissions and types the reply', () async {
      final service = serviceReturning(const {
        'role': 'treasurer',
        'position': 'Treasurer',
        'can_propose_events': true,
        'can_record_finance': true,
      });

      final p = await service.getPermissions();

      expect(sent.single.url.path, endsWith('/auth/permissions'));
      expect(sent.single.method, 'GET');
      expect(p.canRecordFinance, isTrue);
    });
  });
}
