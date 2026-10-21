import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';

/// The SDS Office's remarks and its one electronic signature.
///
/// The server checks the drawing tightly — stroke count, total points,
/// and every coordinate normalised — and a refusal means whoever signed
/// has to draw it again. So the rules are mirrored here and checked
/// before anything is sent.
void main() {
  late List<http.Request> sent;

  SapService serviceReturning(Object body, {int status = 200}) {
    sent = [];
    final client = MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return SapService(ApiClient(httpClient: client));
  }

  Map<String, dynamic> bodyOf() =>
      jsonDecode(sent.single.body) as Map<String, dynamic>;

  final aggregate = {
    'id': 'p1',
    'event_id': 'e1',
    'state': 'sds_signed',
    'version': 13,
    'revision_no': 1,
    'form_code': '020',
    'form_version': '001',
    'details': {'title': 'Hack the Future'},
  };

  SapSignature stroke([int points = 3]) => SapSignature([
    [for (var i = 0; i < points; i++) SapSignaturePoint(i / points, 0.5)],
  ]);

  group('remarks', () {
    test('saving notes sends the sections keyed by wire name', () async {
      final service = serviceReturning(aggregate);

      await service.saveReviewNotes(
        'e1',
        expectedVersion: 12,
        overallRemarks: 'Please revise the projected food budget.',
        sectionRemarks: {
          SapRemarkSection.budget: 'The meal estimate is above the allowance.',
        },
      );

      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, endsWith('/sap-proposal/sds-review'));
      expect(bodyOf()['expected_version'], 12);
      expect(
        bodyOf()['section_remarks'],
        {'budget': 'The meal estimate is above the allowance.'},
      );
    });

    test('blank sections are dropped rather than sent empty', () async {
      final service = serviceReturning(aggregate);

      await service.saveReviewNotes(
        'e1',
        expectedVersion: 12,
        sectionRemarks: {
          SapRemarkSection.budget: '   ',
          SapRemarkSection.clearance: 'Attach the parent consent form.',
        },
      );

      expect(
        bodyOf()['section_remarks'],
        {'clearance': 'Attach the parent consent form.'},
      );
    });

    test('every section the server allows has a name here', () {
      const allowed = [
        'activity_details',
        'budget',
        'support_requests',
        'additional_information',
        'clearance',
        'other',
      ];

      for (final wire in allowed) {
        expect(SapRemarkSection.fromWire(wire), isNotNull, reason: wire);
      }
      expect(SapRemarkSection.values, hasLength(allowed.length));
    });
  });

  group('signing', () {
    test('a signature goes as a list of strokes of points', () async {
      final service = serviceReturning(aggregate);

      final proposal = await service.sdsSign(
        'e1',
        expectedVersion: 12,
        signature: SapSignature([
          [const SapSignaturePoint(0.08, 0.7), const SapSignaturePoint(0.3, 0.25)],
          [const SapSignaturePoint(0.6, 0.5)],
        ]),
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/sap-proposal/sds-sign'));
      expect(bodyOf()['signature_strokes'], [
        [
          {'x': 0.08, 'y': 0.7},
          {'x': 0.3, 'y': 0.25},
        ],
        [
          {'x': 0.6, 'y': 0.5},
        ],
      ]);
      expect(proposal.state, SapState.sdsSigned);
    });

    test('an empty drawing never reaches the server', () async {
      final service = serviceReturning(aggregate);

      expect(
        () => service.sdsSign(
          'e1',
          expectedVersion: 12,
          signature: const SapSignature([]),
        ),
        throwsArgumentError,
      );
      expect(sent, isEmpty);
    });

    test('a stroke with no points in it is caught too', () {
      expect(const SapSignature([[]]).isSendable, isFalse);
    });

    test('a coordinate outside the box is caught', () {
      final off = SapSignature([
        [const SapSignaturePoint(0.5, 1.4)],
      ]);

      expect(off.isSendable, isFalse);
      expect(off.problem, contains('outside'));
    });

    test('the server limits are the ones checked', () {
      expect(
        SapSignature([for (var i = 0; i < 81; i++) stroke(1).strokes.single])
            .problem,
        contains('80'),
      );
      expect(stroke(5001).problem, contains('too detailed'));
      expect(stroke(5000).isSendable, isTrue);
    });
  });
}
