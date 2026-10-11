import '../state/app_state.dart';
import '../theme/brut.dart';

/// One mapping from approval status to meaning, used for the badge, the
/// stripe and the calendar dot alike so the three can never disagree.
///
/// Draft is deliberately the quietest: it is nobody's queue yet. Completed
/// reads like approved, since it is the settled end state. Both pending
/// stages are yellow — they mean the same thing to the person looking at
/// the list, and the label says which desk it is on.
BrutTone eventStatusTone(EventApprovalStatus s) => switch (s) {
  EventApprovalStatus.draft => BrutTone.neutral,
  EventApprovalStatus.approved ||
  EventApprovalStatus.completed => BrutTone.mint,
  EventApprovalStatus.rejected => BrutTone.coral,
  EventApprovalStatus.pendingAdmin ||
  EventApprovalStatus.pendingAdviser => BrutTone.sun,
};
