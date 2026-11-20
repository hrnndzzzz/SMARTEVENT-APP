/// What a notification is *about*, in one word, and in what colour.
///
/// The header pill shows this rather than the notice's title. A title
/// is a sentence and the header has room for about seven characters;
/// the useful part at a glance is which part of the app wants you —
/// an approval, an expense, the stockroom — and whether it went well.
///
/// ## Why this reads the kind in two halves
///
/// The backend names kinds `area_outcome`: `sap_returned`,
/// `expense_approved`. The area decides the word and the outcome
/// decides the colour, so a kind nobody has seen before still comes
/// out sensibly as long as it follows the pattern. A kind that follows
/// no pattern at all falls back to "Update" in the neutral tone, which
/// is honest rather than wrong.
///
/// ## What actually exists today
///
/// The backend raises exactly one kind, `registration_confirmation`,
/// from `queue_registration_confirmation`. The SAP and expense kinds
/// below are the ones the demo seeds and the ones the model's own
/// documentation says are coming; against the real server they will
/// not appear until somebody raises them. The mapping is written for
/// both so the pill does not need changing when they do.
library;

import '../theme/brut.dart';

/// One word and a tone for a notice kind.
typedef NoticeBadge = ({String label, BrutTone tone});

/// The word, from the part of the app the kind belongs to.
String noticeArea(String kind) {
  final area = kind.split('_').first;
  return switch (area) {
    'sap' || 'proposal' || 'event' => 'Approval',
    'expense' || 'receipt' => 'Expense',
    'income' => 'Income',
    'inventory' || 'stock' => 'Inventory',
    'registration' || 'account' || 'user' => 'Account',
    'report' || 'export' => 'Report',
    'budget' => 'Budget',
    _ => 'Update',
  };
}

/// The colour, from how it turned out.
///
/// Mint for something that went through, coral for something that did
/// not, sun for something now waiting on a person. Anything else is
/// neutral: a notice with no outcome in its name is news, not a
/// verdict, and colouring it would be inventing one.
BrutTone noticeOutcome(String kind) {
  final parts = kind.split('_');
  if (parts.length < 2) return BrutTone.neutral;
  final outcome = parts.last;
  return switch (outcome) {
    'approved' ||
    'signed' ||
    'completed' ||
    'confirmed' ||
    'confirmation' ||
    'evaluated' => BrutTone.mint,
    'rejected' ||
    'returned' ||
    'failed' ||
    'withdrawn' ||
    'cancelled' => BrutTone.coral,
    'submitted' || 'pending' || 'waiting' || 'due' || 'low' => BrutTone.sun,
    _ => BrutTone.neutral,
  };
}

/// Both halves together.
NoticeBadge noticeBadge(String kind) =>
    (label: noticeArea(kind), tone: noticeOutcome(kind));
