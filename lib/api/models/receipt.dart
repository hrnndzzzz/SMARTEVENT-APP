/// A receipt attached to an expense or an income — the backend's
/// `ReceiptOut`.
///
/// Duplicate detection lives here. Two different things can happen:
///
///  * an **exact** duplicate (same URL, file or reference) is refused
///    outright with a 409 and never becomes a receipt at all;
///  * a **similar** one — same merchant and amount, nearby date — is saved
///    but held at [ReceiptReviewStatus.pending] until a reviewer decides.
///
/// Neither is proof of anything. A flag says "these look alike, someone
/// should check", and the UI must not present it as established fraud.
class Receipt {
  final String id;
  final String organizationId;
  final String departmentId;
  final String eventId;

  /// Exactly one of these is set — a receipt belongs to one transaction.
  final String? expenseId;
  final String? incomeId;

  /// Required and never blank: what the spending was actually for.
  final String purpose;

  final String receiptUrl;
  final String? merchant;
  final String? receiptNumber;
  final DateTime issuedOn;
  final double amount;

  final bool isFlagged;

  /// Other receipts this one resembles. Load them to show a comparison —
  /// the reviewer needs to see both to decide.
  final List<String> similarReceiptIds;

  final ReceiptReviewStatus reviewStatus;
  final String? reviewReason;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  final String recordedBy;
  final DateTime createdAt;

  Receipt({
    required this.id,
    required this.organizationId,
    required this.departmentId,
    required this.eventId,
    required this.expenseId,
    required this.incomeId,
    required this.purpose,
    required this.receiptUrl,
    required this.merchant,
    required this.receiptNumber,
    required this.issuedOn,
    required this.amount,
    required this.isFlagged,
    required this.similarReceiptIds,
    required this.reviewStatus,
    required this.reviewReason,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.recordedBy,
    required this.createdAt,
  });

  bool get isForExpense => expenseId != null;

  /// Waiting on a reviewer. While pending, it blocks approval of its
  /// expense and withholds its income from totals.
  bool get isAwaitingReview => reviewStatus == ReceiptReviewStatus.pending;

  /// A decision has been recorded and cannot be revised — rewriting the
  /// metadata does not erase a flag.
  bool get isReviewSettled =>
      reviewStatus == ReceiptReviewStatus.cleared ||
      reviewStatus == ReceiptReviewStatus.rejected;

  bool get hasSimilar => similarReceiptIds.isNotEmpty;

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      departmentId: json['department_id'] as String,
      eventId: json['event_id'] as String,
      expenseId: json['expense_id'] as String?,
      incomeId: json['income_id'] as String?,
      purpose: json['purpose'] as String,
      receiptUrl: json['receipt_url'] as String,
      merchant: json['merchant'] as String?,
      receiptNumber: json['receipt_number'] as String?,
      issuedOn: DateTime.parse(json['issued_on'] as String),
      amount: (json['amount'] as num).toDouble(),
      isFlagged: json['is_flagged'] as bool? ?? false,
      similarReceiptIds: [
        for (final id in (json['similar_receipt_ids'] as List? ?? const []))
          id as String,
      ],
      reviewStatus: receiptReviewStatusFromWire(json['review_status'] as String?),
      reviewReason: json['review_reason'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] == null
          ? null
          : DateTime.parse(json['reviewed_at'] as String),
      recordedBy: json['recorded_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Where a receipt stands with duplicate review.
///
/// [clear] means nothing resembled it — not that someone approved it.
enum ReceiptReviewStatus { clear, pending, cleared, rejected }

extension ReceiptReviewStatusNaming on ReceiptReviewStatus {
  String get wireName => name;

  String get label => switch (this) {
        ReceiptReviewStatus.clear => 'No similar receipts',
        ReceiptReviewStatus.pending => 'Awaiting review',
        ReceiptReviewStatus.cleared => 'Reviewed — cleared',
        ReceiptReviewStatus.rejected => 'Reviewed — rejected',
      };

  /// What this status means for the transaction it belongs to.
  String get consequence => switch (this) {
        ReceiptReviewStatus.clear => 'Counts toward totals as normal.',
        ReceiptReviewStatus.pending =>
          'Blocks approval of its expense, and its income is withheld from '
              'totals until reviewed.',
        ReceiptReviewStatus.cleared =>
          'A reviewer confirmed it is not a duplicate.',
        ReceiptReviewStatus.rejected =>
          'A reviewer rejected it. Its income stays withheld and its expense '
              'cannot be approved.',
      };
}

/// Unknown values read as [ReceiptReviewStatus.pending] rather than
/// [clear]: treating something unrecognized as needing a look is the safer
/// mistake.
ReceiptReviewStatus receiptReviewStatusFromWire(String? value) =>
    switch (value) {
      'clear' => ReceiptReviewStatus.clear,
      'pending' => ReceiptReviewStatus.pending,
      'cleared' => ReceiptReviewStatus.cleared,
      'rejected' => ReceiptReviewStatus.rejected,
      _ => ReceiptReviewStatus.pending,
    };

/// A reviewer's decision on a flagged receipt. Only these two are
/// submittable — `clear` and `pending` are states, not decisions.
enum ReceiptDecision { cleared, rejected }

extension ReceiptDecisionNaming on ReceiptDecision {
  String get wireName => name;

  String get label => switch (this) {
        ReceiptDecision.cleared => 'Clear it',
        ReceiptDecision.rejected => 'Reject it',
      };
}
