import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';

/// Every state the backend's CHECK constraint allows has to parse here.
/// An unknown one comes back null and the proposal renders as nothing in
/// particular, which is how `sds_signed` went missing when the SDS review
/// and signing flow landed.
void main() {
  test('every state the server can store is understood', () {
    const stored = [
      'draft',
      'pending_sap_review',
      'revision_requested',
      'sds_signed',
      'approved',
      'completed',
      'rejected',
    ];

    for (final wire in stored) {
      expect(
        SapState.fromWire(wire),
        isNotNull,
        reason: 'the server can store $wire, so the app must read it',
      );
    }
  });

  test('a signed revision is out of the proposer\'s hands', () {
    expect(SapState.sdsSigned.isProposerEditable, isFalse);
    expect(SapState.draft.isProposerEditable, isTrue);
    expect(SapState.revisionRequested.isProposerEditable, isTrue);
  });

  test('an unknown state is still reported as unknown', () {
    expect(SapState.fromWire('something_new'), isNull);
    expect(SapState.fromWire(null), isNull);
  });
}
