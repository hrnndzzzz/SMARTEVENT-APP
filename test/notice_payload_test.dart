import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/notification.dart';

/// The backend attached a payload to workflow notices on 24 Oct, so a
/// notice can be opened instead of only read. It is declared as a
/// string-or-int map and is null on every row raised before that, which
/// is the case worth pinning: a notice that cannot say where it points
/// must stay readable rather than crash the bell.
void main() {
  Map<String, dynamic> row(Object? payload) => {
    'id': 'n1',
    'kind': 'sap_workflow',
    'title': 'SAP proposal submitted',
    'body': 'Sent to the SDS Office: Hack the Future.',
    'read_at': null,
    'email_status': 'pending',
    'created_at': '2026-10-24T09:00:00Z',
    if (payload != null) 'payload': payload,
  };

  test('a workflow notice knows the event it is about', () {
    final notice = AppNotice.fromJson(
      row({
        'event_id': 'e1',
        'proposal_id': 'p1',
        'revision_no': 1,
        'state': 'pending_sap_review',
        'action': 'sap_submitted',
      }),
    );

    expect(notice.eventId, 'e1');
    expect(notice.payload['revision_no'], 1, reason: 'ints survive as ints');
    expect(notice.payload['action'], 'sap_submitted');
  });

  test('a notice raised before payloads existed is still readable', () {
    final notice = AppNotice.fromJson(row(null));

    expect(notice.payload, isEmpty);
    expect(notice.eventId, isNull);
    expect(notice.title, 'SAP proposal submitted');
  });

  test('an explicit null payload is not a missing key', () {
    // response_model_exclude_unset means the key may be absent, but a
    // stored null comes back as null. Both have to land on empty.
    final notice = AppNotice.fromJson(row(null)..['payload'] = null);

    expect(notice.payload, isEmpty);
    expect(notice.eventId, isNull);
  });

  test('a payload without an event id leaves the notice unopenable', () {
    final notice = AppNotice.fromJson(row({'action': 'account_confirmed'}));

    expect(notice.eventId, isNull);
    expect(notice.payload['action'], 'account_confirmed');
  });

  test('an empty event id counts as none, not as an event called ""', () {
    final notice = AppNotice.fromJson(row({'event_id': ''}));

    expect(notice.eventId, isNull);
  });

  test('marking one read keeps where it points', () {
    final notice = AppNotice.fromJson(row({'event_id': 'e1'}));

    final read = notice.markedRead();

    expect(read.readAt, isNotNull);
    expect(read.eventId, 'e1', reason: 'reading it must not close it');
  });
}
