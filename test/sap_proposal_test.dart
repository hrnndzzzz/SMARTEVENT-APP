import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';

/// The backend rejects unknown JSON keys and every field name here is
/// taken from the contract, so these tests exist mainly to pin the wire
/// format: a renamed key fails here rather than as an unexplained 422 on
/// a phone during a defence.
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
    return SapService(
      ApiClient(httpClient: client),
    );
  }

  Map<String, dynamic> bodyOf() =>
      jsonDecode(sent.single.body) as Map<String, dynamic>;

  final aggregate = {
    'id': 'p1',
    'event_id': 'e1',
    'state': 'draft',
    'version': 3,
    'revision_no': 0,
    'form_code': '020',
    'form_version': '001',
    'details': {
      'title': 'Hack the Future',
      'activity_date': '2026-10-28',
      'start_time': '08:00:00',
      'end_time': '11:00:00',
      'modality': 'online',
      'setting': 'online',
      'expected_students': 145,
      'total_budget': '2500.00',
      'core_values': ['courage', 'humility'],
      'egas': [1, 2, 3, 4],
    },
    'program_flow': [
      {'start': '08:00:00', 'end': '11:00:00', 'activity': 'Seminar'},
    ],
    'budget_items': [
      {'particulars': 'Speaker', 'amount': '2000.00'},
    ],
    'support_requests': [
      {'type': 'projector'},
    ],
    'affected_classes': const [],
  };

  group('parsing', () {
    test('an aggregate reads the fields the contract names', () async {
      final service = serviceReturning(aggregate);
      final p = await service.fetch('e1');

      expect(p.id, 'p1');
      expect(p.state, SapState.draft);
      expect(p.version, 3);
      expect(p.revisionNo, 0);
      expect(p.details.title, 'Hack the Future');
      expect(p.details.modality, SapModality.online);
      expect(p.details.setting, SapSetting.online);
      expect(p.details.expectedStudents, 145);
      expect(p.details.coreValues, [
        SapCoreValue.courage,
        SapCoreValue.humility,
      ]);
      expect(p.details.egas, [1, 2, 3, 4]);
      expect(p.programFlow.single.activity, 'Seminar');
      expect(p.budgetItems.single.amount, '2000.00');
      expect(p.supportRequests.single.type, SapSupportType.projector);
      expect(p.affectedClasses, isEmpty);
    });

    test('money stays a string rather than becoming a double', () async {
      final service = serviceReturning(aggregate);
      final p = await service.fetch('e1');

      // Exact decimal equality is checked server-side against the lines,
      // so a float round-trip here is a 422 nobody can explain.
      expect(p.details.totalBudget, '2500.00');
      expect(p.details.totalBudget, isA<String>());
    });

    test('an unknown enum value does not throw', () async {
      final service = serviceReturning({
        ...aggregate,
        'details': {...aggregate['details'] as Map, 'modality': 'telepathy'},
      });
      final p = await service.fetch('e1');
      expect(p.details.modality, isNull);
    });

    test('times survive the round trip', () {
      expect(SapTime.fromWire('08:00:00'), const SapTime(8, 0));
      expect(SapTime.fromWire('23:59:59'), const SapTime(23, 59, 59));
      expect(const SapTime(8, 5).wire, '08:05:00');
      expect(const SapTime(0, 0).label, '12:00 AM');
      expect(const SapTime(12, 0).label, '12:00 PM');
      expect(const SapTime(13, 30).label, '1:30 PM');
      expect(SapTime.fromWire('nonsense'), isNull);
      expect(SapTime.fromWire('25:00:00'), isNull);
    });
  });

  group('sending', () {
    test('a partial save sends only the fields that were set', () async {
      final service = serviceReturning(aggregate);
      await service.saveDetails(
        'e1',
        expectedVersion: 2,
        details: const SapDetails(title: 'Hack the Future', expectedStudents: 145),
      );

      expect(sent.single.method, 'PATCH');
      expect(sent.single.url.path, '/events/e1/sap-proposal');
      expect(bodyOf()['expected_version'], 2);

      // Untouched fields must be absent, not null: the backend rejects
      // unknown keys and a null would wipe a stored value.
      final details = bodyOf()['details'] as Map;
      expect(details.keys.toSet(), {'title', 'expected_students'});
    });

    test('collections are replaced wholesale', () async {
      final service = serviceReturning(aggregate);
      await service.replaceBudgetItems(
        'e1',
        expectedVersion: 4,
        items: const [
          SapBudgetItem(particulars: 'Speaker', amount: '2000.00'),
          SapBudgetItem(particulars: 'Certificates', amount: '300.00'),
        ],
      );

      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, '/events/e1/sap-proposal/budget-items');
      expect(bodyOf()['expected_version'], 4);
      expect((bodyOf()['items'] as List).length, 2);
      expect((bodyOf()['items'] as List).first, {
        'particulars': 'Speaker',
        'amount': '2000.00',
      });
    });

    test('an empty affected-classes list is sent, clearing the declaration', () async {
      final service = serviceReturning(aggregate);
      await service.replaceAffectedClasses(
        'e1',
        expectedVersion: 5,
        items: const [],
      );
      expect(bodyOf()['items'], isEmpty);
    });

    test('a checkpoint sends the evidence beside the version', () async {
      final service = serviceReturning({
        'state': 'pending_sap_review',
        'revision_no': 1,
        'version': 11,
        'completed_count': 1,
        'total_count': 9,
        'steps': const [],
      });

      await service.recordCheckpoint(
        'e1',
        stepId: 's2',
        expectedVersion: 10,
        evidence: SapCheckpointEvidence(
          signerName: 'Physical Signer Name',
          signerReference: 'institution-person-002',
          assignedUserId: null,
          physicalSignatureDate: DateTime(2026, 10, 17),
          remarks: 'Paper inspected by SDS',
          recordedOnBehalf: true,
        ),
      );

      expect(
        sent.single.url.path,
        '/events/e1/sap-proposal/workflow/s2/record',
      );
      expect(bodyOf()['expected_version'], 10);
      expect(bodyOf()['signer_name'], 'Physical Signer Name');
      expect(bodyOf()['signer_reference'], 'institution-person-002');
      expect(bodyOf()['physical_signature_date'], '2026-10-17');
      expect(bodyOf()['recorded_on_behalf'], isTrue);
    });

    test('evaluation sends the outcome by its wire name', () async {
      final service = serviceReturning(aggregate);
      await service.evaluate(
        'e1',
        expectedVersion: 23,
        outcome: SapEvaluationOutcome.canceled,
        remarks: 'Called off.',
      );
      expect(bodyOf()['outcome'], 'canceled');
      expect(bodyOf()['remarks'], 'Called off.');
    });
  });

  group('failures', () {
    test('409 becomes a conflict the caller must reload for', () async {
      final service = serviceReturning({'detail': 'Stale version'}, status: 409);

      await expectLater(
        service.submit('e1', expectedVersion: 1),
        throwsA(isA<SapVersionConflict>()),
      );
    });

    test('404 reads as the slice not being deployed', () async {
      final service = serviceReturning({'detail': 'Not Found'}, status: 404);

      await expectLater(
        service.fetch('e1'),
        throwsA(isA<SapUnavailable>()),
      );
    });

    test('422 stays an ApiException so the draft can be kept', () async {
      final service = serviceReturning({
        'detail': [
          {
            'loc': ['body', 'details', 'end_time'],
            'msg': 'End must be after start',
            'type': 'value_error',
          },
        ],
      }, status: 422);

      await expectLater(
        service.submit('e1', expectedVersion: 1),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('workflow', () {
    test('nine slots parse, and the next actionable one is found', () async {
      final service = serviceReturning({
        'state': 'pending_sap_review',
        'revision_no': 1,
        'version': 11,
        'completed_count': 1,
        'total_count': 9,
        'steps': [
          {
            'id': 's1',
            'slot': 1,
            'position': 'ACPES President',
            'display_label': 'Prepared by',
            'revision_no': 1,
            'status': 'recorded',
            'actionable': false,
            'evidence': {
              'signer_name': 'Jansen Ashley A. De Vera',
              'signer_reference': 'institution-person-001',
              'physical_signature_date': '2026-09-26',
              'recorded_on_behalf': true,
            },
          },
          {
            'id': 's2',
            'slot': 2,
            'position': 'ACPES Moderator',
            'display_label': 'Reviewed by',
            'revision_no': 1,
            'status': 'pending',
            'actionable': true,
            'evidence': null,
          },
        ],
      });

      final w = await service.workflow('e1');
      expect(w.totalCount, 9);
      expect(w.completedCount, 1);
      expect(w.steps.first.isRecorded, isTrue);
      expect(w.steps.first.evidence!.signerName, 'Jansen Ashley A. De Vera');
      expect(w.nextActionable!.id, 's2');
      expect(w.nextActionable!.displayLabel, 'Reviewed by');
    });

    test('no steps before first submission', () async {
      final service = serviceReturning({
        'state': 'draft',
        'revision_no': 0,
        'version': 1,
        'completed_count': 0,
        'total_count': 9,
        'steps': const [],
      });
      final w = await service.workflow('e1');
      expect(w.hasStarted, isFalse);
      expect(w.nextActionable, isNull);
    });
  });

  group('states', () {
    test('only draft and returned are proposer-editable', () {
      expect(SapState.draft.isProposerEditable, isTrue);
      expect(SapState.revisionRequested.isProposerEditable, isTrue);
      expect(SapState.pendingReview.isProposerEditable, isFalse);
      expect(SapState.approved.isProposerEditable, isFalse);
      expect(SapState.completed.isProposerEditable, isFalse);
    });

    test('off_campus is not a setting this slice accepts', () {
      expect(SapSetting.fromWire('off_campus'), isNull);
      expect(SapSetting.values.map((s) => s.wireName), ['on_campus', 'online']);
    });
  });
}
