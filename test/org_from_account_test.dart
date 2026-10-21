import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/demo_data.dart';

/// Which organization an event belongs to is a fact about the account,
/// not a choice made per event: a JPSSITE officer proposes for JPSSITE.
void main() {
  test('the demo knows the two societies CITE has', () {
    final app = AppState()..enterDemo();

    expect(app.organizations.map((o) => o.code), containsAll(['ACPES', 'JPSSITE']));
    expect(app.departments.single.code, 'CITE');
  });

  test('the account belongs to one of them', () {
    final app = AppState()..enterDemo();
    final orgId = app.currentAccount!.organizationId;

    expect(
      app.organizations.where((o) => o.id == orgId),
      isNotEmpty,
      reason: 'the account must belong to an organization that exists',
    );
  });

  test('BSIT is not one of them', () {
    // It is a course. On the paper it goes in Program/Course, beside an
    // Organization that is a society. Offering it as an organization
    // would print it in the wrong box.
    expect(
      DemoData.organizations().map((o) => o.code),
      isNot(contains('BSIT')),
    );
  });
}
