import 'api_client.dart';
import 'models/receipt.dart';
import 'models/remote_expense.dart' show receiptContentTypeFor;

/// Receipts, duplicate detection and independent review.
///
/// There is no DELETE and no general PATCH: `POST /receipts` upserts the
/// receipt for a transaction, subject to the backend's own immutability
/// rules, and a settled review cannot be rewritten.
class ReceiptService {
  final ApiClient _client;
  ReceiptService(this._client);

  /// `GET /receipts`.
  ///
  /// [flaggedOnly] and [reviewStatus] are real server-side filters — the
  /// pending queue is built from them rather than by filtering locally.
  Future<List<Receipt>> list({
    String? eventId,
    bool flaggedOnly = false,
    ReceiptReviewStatus? reviewStatus,
  }) async {
    final query = <String, String>{
      if (eventId != null) 'event_id': eventId,
      if (flaggedOnly) 'flagged_only': 'true',
      if (reviewStatus != null) 'review_status': reviewStatus.wireName,
    };
    final response = await _client.get(
      '/receipts',
      query: query.isEmpty ? null : query,
    );
    return (response as List)
        .map((json) => Receipt.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Receipt> get(String receiptId) async {
    final response = await _client.get('/receipts/$receiptId');
    return Receipt.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /receipts` — records or updates the receipt on one transaction.
  ///
  /// Exactly one of [expenseId] or [incomeId]; the backend rejects both or
  /// neither. Event and department scope are derived from that transaction,
  /// never sent as free text.
  ///
  /// A known exact duplicate URL, file or reference comes back as a 409. A
  /// merely *similar* one succeeds and lands in the pending queue.
  Future<Receipt> record({
    String? expenseId,
    String? incomeId,
    required String receiptUrl,
    required String purpose,
    String? merchant,
    String? receiptNumber,
    DateTime? issuedOn,
    String? amount,
  }) async {
    final response = await _client.post('/receipts', body: {
      if (expenseId != null) 'expense_id': expenseId,
      if (incomeId != null) 'income_id': incomeId,
      'receipt_url': receiptUrl,
      'purpose': purpose,
      if (merchant != null) 'merchant': merchant,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (issuedOn != null)
        'issued_on': issuedOn.toIso8601String().split('T').first,
      if (amount != null) 'amount': amount,
    });
    return Receipt.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /receipts/{id}/upload` — attaches the image to an existing
  /// receipt. The receipt record has to exist first.
  Future<Receipt> upload(
    String receiptId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final contentType = receiptContentTypeFor(filename);
    if (contentType == null) {
      throw ArgumentError(
        'Receipts must be JPEG, PNG, WebP or HEIC — got "$filename".',
      );
    }
    final response = await _client.upload(
      '/receipts/$receiptId/upload',
      field: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
    return Receipt.fromJson((response as Map).cast<String, dynamic>());
  }

  /// `POST /receipts/{id}/review` — an independent reviewer resolves a
  /// pending similar-receipt flag.
  ///
  /// [reason] must be at least 10 characters: a decision that withholds
  /// income or blocks an approval has to say why. Only pending receipts can
  /// be reviewed, and the result is final.
  Future<Receipt> review(
    String receiptId, {
    required ReceiptDecision decision,
    required String reason,
  }) async {
    final response = await _client.post('/receipts/$receiptId/review', body: {
      'decision': decision.wireName,
      'reason': reason,
    });
    return Receipt.fromJson(response as Map<String, dynamic>);
  }

  /// The backend's minimum length for a review reason.
  static const int minReasonLength = 10;
}
