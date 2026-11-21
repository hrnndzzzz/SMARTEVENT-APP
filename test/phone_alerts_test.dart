import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/notification.dart';
import 'package:smartevent/state/phone_alerts.dart';

/// Which unread notices the background check puts on the phone.
void main() {
  AppNotice notice(String id) => AppNotice(
    id: id,
    kind: 'sap_workflow',
    title: 'SAP proposal returned',
    body: 'Hack the Future was returned for changes.',
    readAt: null,
    emailStatus: 'pending',
    createdAt: DateTime(2026, 11, 21),
  );

  test('the first check after signing in only takes note', () {
    final unread = [notice('a'), notice('b')];
    expect(freshNotices(unread, null), isEmpty);
    expect(rememberShown(unread, null), ['a', 'b']);
  });

  test('later checks show only what is new', () {
    final unread = [notice('c'), notice('a')];
    expect(freshNotices(unread, ['a', 'b']).map((n) => n.id), ['c']);
    expect(rememberShown(unread, ['a', 'b']), ['c', 'a', 'b']);
  });

  test('the record of shown notices stays small', () {
    final old = [for (var i = 0; i < 250; i++) 'old$i'];
    final kept = rememberShown([notice('new')], old);
    expect(kept.length, 200);
    expect(kept.first, 'new');
  });
}
