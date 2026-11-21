import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/sap_form.dart';

/// The server rejects a proposal nobody decided 30 days before the
/// activity. The banners must not blame the SDS Office for that.
void main() {
  test('a rejection with remarks and no reviewer reads as automatic', () {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(
        state: SapState.rejected,
        returnRemarks: 'Rejected automatically: no decision was made.',
      );
    expect(form.autoRejected, isTrue);
    expect(form.rejectedBy, startsWith('Rejected automatically'));
  });

  test('the SDS Office rejecting it still says so', () {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(state: SapState.rejected, sdsRemarks: 'Not allowed');
    expect(form.autoRejected, isFalse);
    expect(form.rejectedBy, 'Rejected by the SDS Office');
  });

  test('a returned proposal is not a rejection', () {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(
        state: SapState.revisionRequested,
        returnedBy: SapReturnedBy.dean,
        returnRemarks: 'Fix the budget',
      );
    expect(form.autoRejected, isFalse);
  });
}
