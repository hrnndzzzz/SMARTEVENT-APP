import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/state/sap_form.dart';

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
    // Exactly as app/services/sap.py builds it: one nested object, keyed
    // the way the endpoints are named.
    'collections': {
      'program-flow': [
        {'start': '08:00:00', 'end': '11:00:00', 'activity': 'Seminar'},
      ],
      'budget-items': [
        {'particulars': 'Speaker', 'quantity': 1, 'amount': '2000.00'},
      ],
      'support-requests': [
        {'type': 'projector', 'quantity': 1, 'specify': ''},
      ],
      'affected-classes': const [],
    },
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

    test('collections come out of the nested object', () async {
      // Reading these from the top level parsed four empty lists and
      // lost everything that had been saved.
      final service = serviceReturning(aggregate);
      final p = await service.fetch('e1');

      expect(p.programFlow, hasLength(1));
      expect(p.budgetItems, hasLength(1));
      expect(p.supportRequests, hasLength(1));
      expect(p.affectedClasses, isEmpty);
    });

    test('a missing collections object is not a crash', () async {
      final service = serviceReturning({...aggregate}..remove('collections'));
      final p = await service.fetch('e1');
      expect(p.programFlow, isEmpty);
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
      // quantity goes on every row, including the ordinary one. The
      // server defaults it to 1 and stores it either way, so sending it
      // makes the payload say what the row will actually be.
      expect((bodyOf()['items'] as List).first, {
        'particulars': 'Speaker',
        'quantity': 1,
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

    test('a support request always carries a quantity', () async {
      // The backend declares `quantity: int = Field(ge=1)` with no
      // default, so omitting it is a 422 on every row.
      final service = serviceReturning(aggregate);
      await service.replaceSupportRequests(
        'e1',
        expectedVersion: 6,
        items: const [SapSupportRequest(type: SapSupportType.projector)],
      );

      final item = (bodyOf()['items'] as List).single as Map;
      expect(item['quantity'], 1);
      expect(item['type'], 'projector');
    });

    test('a quantity below one is lifted to one', () async {
      final service = serviceReturning(aggregate);
      await service.replaceSupportRequests(
        'e1',
        expectedVersion: 7,
        items: const [
          SapSupportRequest(type: SapSupportType.chairs, quantity: 0),
        ],
      );
      expect(((bodyOf()['items'] as List).single as Map)['quantity'], 1);
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
      expect(SapState.pendingDepartmentReview.isProposerEditable, isFalse);
      expect(SapState.pendingReview.isProposerEditable, isFalse);
      expect(SapState.approved.isProposerEditable, isFalse);
      expect(SapState.completed.isProposerEditable, isFalse);
    });

    test('all three of the paper settings are accepted', () {
      // off_campus was refused by the first slice and is taken now. It
      // carries conditions the other two do not; those are Part 1's to
      // enforce, not this enum's.
      expect(SapSetting.fromWire('off_campus'), SapSetting.offCampus);
      expect(SapSetting.values.map((s) => s.wireName), [
        'on_campus',
        'off_campus',
        'online',
      ]);
    });
  });

  group('returned by', () {
    // `returned_by` arrives with a return and says whose remarks
    // `return_remarks` holds: the Moderator, the Dean or the SDS Office.

    test('names who sent it back, worded to follow "Returned by"', () async {
      for (final (wire, who, label) in [
        ('moderator', SapReturnedBy.moderator, 'the Moderator'),
        ('dean', SapReturnedBy.dean, 'the Dean'),
        ('sds', SapReturnedBy.sds, 'the SDS Office'),
      ]) {
        final p = await serviceReturning({
          ...aggregate,
          'state': 'revision_requested',
          'returned_by': wire,
        }).fetch('e1');

        expect(p.returnedBy, who, reason: wire);
        expect(who.wireName, wire);
        expect(who.label, label);
      }
    });

    test('is empty when absent, null or not one the app knows', () async {
      for (final extra in <Map<String, dynamic>>[
        {},
        {'returned_by': null},
        {'returned_by': 'registrar'},
      ]) {
        final p = await serviceReturning({...aggregate, ...extra}).fetch('e1');
        expect(p.returnedBy, isNull, reason: '$extra');
      }
    });

    test('a form loaded from the server exposes it', () async {
      final form = SapForm(
        eventId: 'e1',
        service: serviceReturning({
          ...aggregate,
          'state': 'revision_requested',
          'returned_by': 'dean',
          'return_remarks': 'Cut the budget.',
        }),
      );
      await form.load();

      expect(form.returnedBy, SapReturnedBy.dean);
    });

    test('a form can be seeded as returned, or as resubmitted', () {
      final returned = SapForm(eventId: 'e1')
        ..seedLocally(
          state: SapState.revisionRequested,
          returnedBy: SapReturnedBy.moderator,
          revisionNo: 2,
        );
      expect(returned.returnedBy, SapReturnedBy.moderator);
      expect(returned.revisionNo, 2);
      expect(returned.isResubmission, isTrue);

      final plain = SapForm(eventId: 'e1')..seedLocally();
      expect(plain.returnedBy, isNull);
      expect(plain.revisionNo, 0, reason: 'seeding has always started at 0');
      expect(plain.isResubmission, isFalse);
    });
  });

  group('withdrawal', () {
    // POST .../sap-proposal/withdraw, added by the backend on 24 Oct.
    // The proposer takes an unreviewed proposal back to draft.

    test('sends only the version, to the withdraw path', () async {
      final service = serviceReturning({...aggregate, 'state': 'draft'});

      await service.withdraw('e1', expectedVersion: 3);

      expect(sent.single.method, 'POST');
      expect(
        sent.single.url.path,
        endsWith('/events/e1/sap-proposal/withdraw'),
      );
      expect(bodyOf(), {'expected_version': 3});
    });

    test('comes back as a draft with the revision intact', () async {
      // The server keeps revision_no and re-stages the attachments, so
      // withdrawing is not a discard: the submitted revision survives.
      final service = serviceReturning({
        ...aggregate,
        'state': 'draft',
        'version': 4,
        'revision_no': 1,
      });

      final proposal = await service.withdraw('e1', expectedVersion: 3);

      expect(proposal.state, SapState.draft);
      expect(proposal.revisionNo, 1);
      expect(proposal.version, 4, reason: 'the write bumped the version');
    });

    test('a started review is refused, and the reason is kept', () async {
      final service = serviceReturning({
        'detail': 'SDS review has started; request a return for changes',
      }, status: 409);

      // Not swallowed into a generic failure: this message is the only
      // thing that tells the proposer to ask for a return instead.
      await expectLater(
        service.withdraw('e1', expectedVersion: 3),
        throwsA(
          isA<SapVersionConflict>().having(
            (e) => e.message,
            'message',
            contains('request a return for changes'),
          ),
        ),
      );
    });

    test('a compliance refusal keeps its message and blockers', () async {
      // The shape `require_pre_activity_clearance` raises on submit.
      final service = serviceReturning({
        'detail': {
          'message': 'Pre-activity compliance is incomplete',
          'blockers': ['Classify the activity as on-campus or off-campus'],
        },
      }, status: 409);

      await expectLater(
        service.submit('e1', expectedVersion: 3),
        throwsA(
          isA<SapVersionConflict>()
              .having(
                (e) => e.message,
                'message',
                startsWith('Pre-activity compliance is incomplete'),
              )
              .having((e) => e.blockers, 'blockers', [
                'Classify the activity as on-campus or off-campus',
              ]),
        ),
      );
    });

    test('a decided proposal is refused by the server, not the client',
        () async {
      final service = serviceReturning({
        'detail': 'Only an unreviewed pending proposal can be withdrawn',
      }, status: 409);

      await expectLater(
        service.withdraw('e1', expectedVersion: 3),
        throwsA(isA<SapVersionConflict>()),
      );
    });

    test('an event with no SAP proposal reads as unavailable', () async {
      final service = serviceReturning({'detail': 'Not Found'}, status: 404);

      await expectLater(
        service.withdraw('e1', expectedVersion: 3),
        throwsA(isA<SapUnavailable>()),
      );
    });
  });

  testWidgets('submitting and printing wait for the server to print', (
    tester,
  ) async {
    // The server fills the official Word form and has Word print it: about
    // 5 s, and up to 90 s when another print is ahead of it. Giving up
    // sooner reports a timeout while the server goes on to finish.
    final client = MockClient((_) => Completer<http.Response>().future);
    final service = SapService(ApiClient(httpClient: client));
    final failed = <String, Object>{};
    service
        .submit('e1', expectedVersion: 1)
        .then<void>((_) {}, onError: (Object e) => failed['submit'] = e);
    service
        .pdf('e1')
        .then<void>((_) {}, onError: (Object e) => failed['pdf'] = e);

    await tester.pump(const Duration(seconds: 60));
    expect(failed, isEmpty, reason: 'gave up while the server was printing');
    await tester.pump(const Duration(minutes: 3)); // let the client time out
  });
}
