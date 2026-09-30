import 'receipt.dart';

/// Money coming in, against an event — the backend's `IncomeOut`.
///
/// There is no edit and no delete endpoint. That is deliberate on the
/// backend's part, so the app must not offer buttons for either, and must
/// not "correct" a figure in local state to paper over it. A wrong entry is
/// a backend conversation, not a negative income row invented client-side.
class Income {
  final String id;
  final String eventId;

  /// Who or what the money actually came from — a sponsor's name, the
  /// paying body. Distinct from [sourceType], and both are shown.
  final String source;

  final FundSource sourceType;

  /// What the money is for. Required and never blank.
  final String purpose;

  final double amount;
  final DateTime receivedOn;

  /// Where its receipt stands. Pending or rejected means this income is
  /// **excluded from totals** — it still appears in the ledger, labelled,
  /// rather than vanishing.
  final ReceiptReviewStatus receiptReviewStatus;

  final String recordedBy;
  final DateTime createdAt;

  Income({
    required this.id,
    required this.eventId,
    required this.source,
    required this.sourceType,
    required this.purpose,
    required this.amount,
    required this.receivedOn,
    required this.receiptReviewStatus,
    required this.recordedBy,
    required this.createdAt,
  });

  /// Excluded from event and consolidated totals because its receipt is
  /// unresolved or was rejected.
  bool get isWithheld =>
      receiptReviewStatus == ReceiptReviewStatus.pending ||
      receiptReviewStatus == ReceiptReviewStatus.rejected;

  String get withheldReason => switch (receiptReviewStatus) {
        ReceiptReviewStatus.pending =>
          'Held out of totals until its receipt is reviewed.',
        ReceiptReviewStatus.rejected =>
          'Held out of totals: its receipt was rejected.',
        _ => '',
      };

  factory Income.fromJson(Map<String, dynamic> json) {
    return Income(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      source: json['source'] as String,
      sourceType: fundSourceFromWire(json['source_type'] as String?),
      purpose: json['purpose'] as String,
      amount: (json['amount'] as num).toDouble(),
      receivedOn: DateTime.parse(json['received_on'] as String),
      receiptReviewStatus:
          receiptReviewStatusFromWire(json['receipt_review_status'] as String?),
      recordedBy: json['recorded_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Where money came from. Recording this is what makes fund-source
/// breakdowns in the financial reports possible at all.
enum FundSource { registrationFees, sponsorship, donation, other }

extension FundSourceNaming on FundSource {
  String get wireName => switch (this) {
        FundSource.registrationFees => 'registration_fees',
        FundSource.sponsorship => 'sponsorship',
        FundSource.donation => 'donation',
        FundSource.other => 'other',
      };

  String get label => switch (this) {
        FundSource.registrationFees => 'Registration fees',
        FundSource.sponsorship => 'Sponsorship',
        FundSource.donation => 'Donation',
        FundSource.other => 'Other',
      };

  String get hint => switch (this) {
        FundSource.registrationFees => 'Collected from participants',
        FundSource.sponsorship => 'From a sponsoring company or body',
        FundSource.donation => 'Given without expectation of return',
        FundSource.other => 'Anything that fits none of the above',
      };
}

/// Unknown values read as [FundSource.other], which is also the backend's
/// own default — an unrecognized source is untyped, not a new category.
FundSource fundSourceFromWire(String? value) => switch (value) {
      'registration_fees' => FundSource.registrationFees,
      'sponsorship' => FundSource.sponsorship,
      'donation' => FundSource.donation,
      _ => FundSource.other,
    };
