/// What a notification is *about*, in one word, and in what colour.
///
/// The header pill shows this rather than the notice's title. A title
/// is a sentence and the header has room for about seven characters;
/// the useful part at a glance is which part of the app wants you —
/// an approval, an expense, the stockroom — and whether it went well.
///
/// ## Why this reads the kind in two halves
///
/// The backend names kinds `area_outcome`: `expense_approved`,
/// `registration_confirmation`. The area decides the word and the
/// outcome decides the colour, so a kind nobody has seen before still
/// comes out sensibly as long as it follows the pattern. A kind that
/// follows no pattern at all falls back to "Update" in the neutral
/// tone, which is honest rather than wrong.
///
/// ## What actually exists today
///
/// The backend raises three kinds: `registration_confirmation`,
/// `sap_workflow` for every step of a proposal's life, and
/// `download_request` when somebody asks for the app on the website.
///
/// `sap_workflow` is the reason [noticeBadge] takes an action as well as
/// a kind: it is the same string whether a proposal was approved or
/// rejected, and the step itself travels in the notice's payload as
/// `action`. The kind alone gives the word; the action gives the
/// colour. The expense, inventory and report kinds below are the ones
/// the demo seeds; against the real server they will not appear until
/// somebody raises them, and the mapping is written for both so the
/// pill does not need changing when they do.
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
    'download' => 'Download',
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
  // Two of the backend's SAP actions do not end in their outcome, so
  // the pattern below would read them backwards. A correction request
  // is a return however the name begins, and an approval recorded with
  // physical evidence is still an approval. Named here rather than by
  // widening the words: a generic 'requested' is not bad news and a
  // generic 'evidence' is not good news, and only these two names mean
  // what they mean.
  final named = switch (kind) {
    'sap_signed_revision_correction_requested' => BrutTone.coral,
    'sap_approved_with_physical_evidence' => BrutTone.mint,
    _ => null,
  };
  if (named != null) return named;

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

/// Both halves together, with [action] standing in for the colour when
/// the kind has none of its own.
///
/// Every SAP notice arrives as `sap_workflow`, which says where it came
/// from and nothing about how it went. Reading the payload's action in
/// that case is what makes the pill say *approved* in mint rather than
/// *approval* in grey. A kind that already carries its own outcome
/// keeps it, so an action can never overrule one.
NoticeBadge noticeBadge(String kind, {String action = ''}) {
  final tone = noticeOutcome(kind);
  return (
    label: noticeArea(kind),
    tone: tone == BrutTone.neutral && action.isNotEmpty
        ? noticeOutcome(action)
        : tone,
  );
}
