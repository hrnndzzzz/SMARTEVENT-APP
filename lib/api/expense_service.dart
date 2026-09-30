import 'api_client.dart';
import 'models/remote_event.dart' show ApprovalRecord;
import 'models/remote_expense.dart';

/// Expenses, receipts on expenses, and purchase completion.
///
/// Two rules shape this whole module:
///
///  * **Approval is a single decision**, not the two-stage workflow events
///    use. One independent Adviser/Admin/Super Admin resolves it.
///  * **Approval does not add stock.** Only `completePurchase` does, and
///    only for asset lines, once payment and delivery are documented.
class ExpenseService {
  final ApiClient _client;
  ExpenseService(this._client);

  Future<List<RemoteExpense>> list() async {
    final response = await _client.get('/expenses');
    return (response as List)
        .map((json) => RemoteExpense.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteExpense> get(String expenseId) async {
    final response = await _client.get('/expenses/$expenseId');
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  /// `GET /expenses/{id}/items` — the itemized breakdown.
  ///
  /// Each line's `amount` is already the line total. Purchase completion
  /// needs these real line IDs, so they must be loaded rather than guessed.
  Future<List<ExpenseLine>> items(String expenseId) async {
    final response = await _client.get('/expenses/$expenseId/items');
    return (response as List)
        .map((json) => ExpenseLine.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<ApprovalRecord>> listApprovals(String expenseId) async {
    final response = await _client.get('/expenses/$expenseId/approvals');
    return (response as List)
        .map((json) => ApprovalRecord.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `POST /expenses` — creates a pending expense.
  ///
  /// [amount] and each line amount are decimal strings, not doubles.
  /// Line totals may not exceed [amount]; the backend rejects that too.
  ///
  /// `event_id` is nullable in the API, but event receipts and stock
  /// purchases need a real event, so callers should require one for those.
  Future<RemoteExpense> create({
    required String categoryId,
    String? eventId,
    required String description,
    required String amount,
    DateTime? expenseDate,
    String? receiptUrl,
    ReceiptDetailsInput? receipt,
    List<ExpenseLineInput> items = const [],
    String? departmentId,
    String? organizationId,
  }) async {
    final response = await _client.post('/expenses', body: {
      'category_id': categoryId,
      if (eventId != null) 'event_id': eventId,
      'description': description,
      'amount': amount,
      if (expenseDate != null) 'expense_date': _asDate(expenseDate),
      if (receiptUrl != null) 'receipt_url': receiptUrl,
      if (receipt != null) 'receipt': receipt.toJson(),
      if (items.isNotEmpty) 'items': [for (final i in items) i.toJson()],
      // Scoped accounts get these applied server-side from their own
      // profile; a Super Admin has no scope and must supply them.
      if (departmentId != null) 'department_id': departmentId,
      if (organizationId != null) 'organization_id': organizationId,
    });
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  /// PATCH semantics — only what changed.
  ///
  /// Saved line items are **not** editable through here, and neither are
  /// status, the OCR fields or the flag: status moves only via approve and
  /// reject so the budget trigger fires exactly once, and the OCR fields
  /// are system-populated. Once a receipt is recorded, event, amount and
  /// date are frozen server-side.
  Future<RemoteExpense> update(
    String expenseId, {
    String? eventId,
    String? categoryId,
    String? description,
    String? amount,
    DateTime? expenseDate,
    String? receiptUrl,
  }) async {
    final response = await _client.patch('/expenses/$expenseId', body: {
      if (eventId != null) 'event_id': eventId,
      if (categoryId != null) 'category_id': categoryId,
      if (description != null) 'description': description,
      if (amount != null) 'amount': amount,
      if (expenseDate != null) 'expense_date': _asDate(expenseDate),
      if (receiptUrl != null) 'receipt_url': receiptUrl,
    });
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  Future<RemoteExpense> approve(String expenseId, {String? remarks}) async {
    final response = await _client.post('/expenses/$expenseId/approve', body: {
      if (remarks != null) 'remarks': remarks,
    });
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  Future<RemoteExpense> reject(String expenseId, {String? remarks}) async {
    final response = await _client.post('/expenses/$expenseId/reject', body: {
      if (remarks != null) 'remarks': remarks,
    });
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  /// Own pending expense, or an administrator. A recorded receipt blocks
  /// deletion — reject it through review instead.
  Future<void> delete(String expenseId) async {
    await _client.delete('/expenses/$expenseId');
  }

  /// `POST /expenses/scan-receipt` — reads a receipt image.
  ///
  /// **Creates nothing.** The image is stored so the photo isn't lost, but
  /// the returned merchant, date, amount and items are only the OCR's
  /// reading and must be reviewed before being submitted through [create].
  ///
  /// Accepts JPEG/JPG, PNG, WebP and HEIC up to 10 MB.
  Future<ScannedReceipt> scanReceipt({
    required List<int> bytes,
    required String filename,
  }) async {
    final response = await _client.upload(
      '/expenses/scan-receipt',
      field: 'file',
      bytes: bytes,
      filename: filename,
      contentType: _receiptType(filename),
    );
    return ScannedReceipt.fromJson((response as Map).cast<String, dynamic>());
  }

  /// `POST /expenses/{id}/receipt` — attaches a receipt image to an
  /// existing pending expense. Returns the updated expense.
  Future<RemoteExpense> uploadReceipt(
    String expenseId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final response = await _client.upload(
      '/expenses/$expenseId/receipt',
      field: 'file',
      bytes: bytes,
      filename: filename,
      contentType: _receiptType(filename),
    );
    return RemoteExpense.fromJson((response as Map).cast<String, dynamic>());
  }

  /// `POST /expenses/{id}/parse-receipt` — the text-based alternative to
  /// [scanReceipt], for when the device did the image-to-text step itself.
  ///
  /// Both are supported integration options. Pick one user flow rather than
  /// exposing two confusing scan buttons.
  Future<RemoteExpense> parseReceipt(
    String expenseId, {
    required String rawText,
  }) async {
    final response = await _client.post(
      '/expenses/$expenseId/parse-receipt',
      body: {'raw_text': rawText},
    );
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /expenses/{id}/complete-purchase` — records payment and
  /// delivery, and is the only thing that turns asset lines into stock.
  ///
  /// Runs once: a second attempt is refused. Consumable lines never enter
  /// stock through this flow.
  Future<RemoteExpense> completePurchase(
    String expenseId,
    PurchaseCompletionInput completion,
  ) async {
    final response = await _client.post(
      '/expenses/$expenseId/complete-purchase',
      body: completion.toJson(),
    );
    return RemoteExpense.fromJson(response as Map<String, dynamic>);
  }

  static String _asDate(DateTime value) =>
      value.toIso8601String().split('T').first;

  /// The backend validates the multipart part's content type against a
  /// fixed allow-list, so an unsupported extension is refused here with a
  /// message that names the problem rather than being sent and rejected.
  static String _receiptType(String filename) {
    final type = receiptContentTypeFor(filename);
    if (type == null) {
      throw ArgumentError(
        'Receipts must be JPEG, PNG, WebP or HEIC — got "$filename".',
      );
    }
    return type;
  }
}
