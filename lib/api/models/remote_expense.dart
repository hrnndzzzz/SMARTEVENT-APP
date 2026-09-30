import 'money.dart';

/// Matches the backend's `ExpenseOut` (see
/// `smartevent-backend/app/schemas.py`).
///
/// Budget only deducts when status becomes "approved", and that happens in
/// a database trigger — never client-side. Approval alone also does NOT add
/// stock: that needs a separate documented purchase completion, which is
/// why all the payment/delivery fields live here too.
class RemoteExpense {
  final String id;
  final String? eventId;
  final String categoryId;
  final String? departmentId;
  final String? organizationId;
  final String description;
  final double amount;
  final DateTime? expenseDate;

  final String? receiptUrl;

  /// What OCR read off the receipt, kept separate from the values the user
  /// confirmed. A mismatch between these and [amount] is exactly what the
  /// flag is for, so neither may be hidden.
  final String? ocrMerchant;
  final String? ocrDate;
  final double? ocrAmount;

  final bool isFlagged;
  final String? flagReason;

  /// "pending" | "approved" | "rejected". A single review decision — not
  /// the two-stage workflow events use.
  final String status;

  final String recordedBy;

  /// Set once the purchase has been recorded as paid and received. Until
  /// then no stock has moved, however long ago the expense was approved.
  final DateTime? purchaseCompletedAt;
  final DateTime? paidOn;
  final DateTime? receivedOn;
  final String? paymentMethod;
  final String? paymentReference;
  final String? purchaseVendor;
  final double? paidAmount;

  final DateTime createdAt;
  final DateTime updatedAt;

  RemoteExpense({
    required this.id,
    required this.eventId,
    required this.categoryId,
    required this.departmentId,
    required this.organizationId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.receiptUrl,
    required this.ocrMerchant,
    required this.ocrDate,
    required this.ocrAmount,
    required this.isFlagged,
    required this.flagReason,
    required this.status,
    required this.recordedBy,
    required this.purchaseCompletedAt,
    required this.paidOn,
    required this.receivedOn,
    required this.paymentMethod,
    required this.paymentReference,
    required this.purchaseVendor,
    required this.paidAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  /// Already paid and received — completing again is refused.
  bool get isPurchaseCompleted => purchaseCompletedAt != null;

  /// A receipt exists, which freezes event, amount and date and prevents
  /// the receipt being detached.
  bool get hasReceipt => receiptUrl != null && receiptUrl!.isNotEmpty;

  /// True when OCR disagrees with the confirmed total. Worth surfacing, but
  /// never as proven wrongdoing.
  bool get ocrAmountDiffers =>
      ocrAmount != null && (ocrAmount! - amount).abs() >= 0.01;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value as String);

  factory RemoteExpense.fromJson(Map<String, dynamic> json) {
    return RemoteExpense(
      id: json['id'] as String,
      eventId: json['event_id'] as String?,
      categoryId: json['category_id'] as String,
      departmentId: json['department_id'] as String?,
      organizationId: json['organization_id'] as String?,
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
      expenseDate: _date(json['expense_date']),
      receiptUrl: json['receipt_url'] as String?,
      ocrMerchant: json['ocr_merchant'] as String?,
      ocrDate: json['ocr_date'] as String?,
      ocrAmount: (json['ocr_amount'] as num?)?.toDouble(),
      isFlagged: json['is_flagged'] as bool? ?? false,
      flagReason: json['flag_reason'] as String?,
      status: json['status'] as String,
      recordedBy: json['recorded_by'] as String,
      purchaseCompletedAt: _date(json['purchase_completed_at']),
      paidOn: _date(json['paid_on']),
      receivedOn: _date(json['received_on']),
      paymentMethod: json['payment_method'] as String?,
      paymentReference: json['payment_reference'] as String?,
      purchaseVendor: json['purchase_vendor'] as String?,
      paidAmount: (json['paid_amount'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Whether a line item becomes stock or is consumed.
///
/// Only assets enter inventory, and only after purchase completion.
/// Consumables never enter stock through this flow at all.
enum ItemCategory { asset, consumable }

extension ItemCategoryNaming on ItemCategory {
  String get wireName => name;

  String get label => switch (this) {
        ItemCategory.asset => 'Asset',
        ItemCategory.consumable => 'Consumable',
      };

  String get description => switch (this) {
        ItemCategory.asset => 'Becomes stock once the purchase is completed.',
        ItemCategory.consumable => 'Used up — never enters stock.',
      };
}

ItemCategory? itemCategoryFromWire(String? value) => switch (value) {
      'asset' => ItemCategory.asset,
      'consumable' => ItemCategory.consumable,
      _ => null,
    };

/// One saved line on an expense — `ExpenseItemOut`.
///
/// [amount] is the line total, already multiplied out. Multiplying it by
/// [quantity] again would double-count.
class ExpenseLine {
  final String id;
  final String expenseId;
  final String name;
  final double amount;
  final ItemCategory? category;
  final int quantity;
  final String unit;

  /// Set for asset lines once purchase completion turned them into stock.
  /// Links through to the inventory record.
  final String? convertedInventoryId;

  final DateTime createdAt;

  ExpenseLine({
    required this.id,
    required this.expenseId,
    required this.name,
    required this.amount,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.convertedInventoryId,
    required this.createdAt,
  });

  bool get isAsset => category == ItemCategory.asset;
  bool get isStocked => convertedInventoryId != null;

  factory ExpenseLine.fromJson(Map<String, dynamic> json) {
    return ExpenseLine(
      id: json['id'] as String,
      expenseId: json['expense_id'] as String,
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: itemCategoryFromWire(json['category'] as String?),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unit: json['unit'] as String? ?? 'pcs',
      convertedInventoryId: json['converted_inventory_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A line being submitted with a new expense — `ExpenseItemInput`.
///
/// Same shape as a scanned item on purpose, so reviewed OCR results pass
/// straight through without reshaping.
class ExpenseLineInput {
  ExpenseLineInput({
    required this.name,
    required this.amount,
    required this.category,
    this.quantity = 1,
    this.unit = 'pcs',
  });

  final String name;

  /// Line total as a decimal string, e.g. `120.00`.
  final String amount;

  final ItemCategory category;
  final int quantity;
  final String unit;

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'category': category.wireName,
        'quantity': quantity,
        'unit': unit,
      };
}

/// Receipt metadata submitted alongside an expense — `ReceiptDetails`.
/// [purpose] is required and must not be blank.
class ReceiptDetailsInput {
  ReceiptDetailsInput({
    required this.receiptUrl,
    required this.purpose,
    this.merchant,
    this.receiptNumber,
    this.issuedOn,
    this.amount,
  });

  final String receiptUrl;
  final String purpose;
  final String? merchant;
  final String? receiptNumber;
  final DateTime? issuedOn;

  /// Decimal string. Must match the transaction it belongs to.
  final String? amount;

  Map<String, dynamic> toJson() => {
        'receipt_url': receiptUrl,
        'purpose': purpose,
        if (merchant != null) 'merchant': merchant,
        if (receiptNumber != null) 'receipt_number': receiptNumber,
        if (issuedOn != null)
          'issued_on': issuedOn!.toIso8601String().split('T').first,
        if (amount != null) 'amount': amount,
      };
}

/// Result of `POST /expenses/scan-receipt` — `ScanReceiptResponse`.
///
/// Deliberately not an expense: **nothing is saved yet**. The image is
/// stored so the photo isn't lost, but merchant, date, amount and items are
/// only the OCR's reading, for the user to correct before `POST /expenses`.
class ScannedReceipt {
  final String receiptUrl;
  final String? merchant;
  final DateTime? date;
  final double? amount;
  final List<ScannedReceiptLine> items;

  ScannedReceipt({
    required this.receiptUrl,
    required this.merchant,
    required this.date,
    required this.amount,
    required this.items,
  });

  factory ScannedReceipt.fromJson(Map<String, dynamic> json) {
    return ScannedReceipt(
      receiptUrl: json['receipt_url'] as String,
      merchant: json['merchant'] as String?,
      date: json['date'] == null ? null : DateTime.tryParse(json['date'] as String),
      amount: (json['amount'] as num?)?.toDouble(),
      items: [
        for (final item in (json['items'] as List? ?? const []))
          ScannedReceiptLine.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  /// Turns the reviewed scan into lines for `POST /expenses`.
  List<ExpenseLineInput> toLineInputs() => [
        for (final item in items)
          ExpenseLineInput(
            name: item.name,
            amount: MoneyInput.fromDouble(item.amount),
            category: item.category ?? ItemCategory.consumable,
          ),
      ];
}

class ScannedReceiptLine {
  final String name;
  final double amount;
  final ItemCategory? category;

  ScannedReceiptLine({
    required this.name,
    required this.amount,
    required this.category,
  });

  factory ScannedReceiptLine.fromJson(Map<String, dynamic> json) {
    return ScannedReceiptLine(
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: itemCategoryFromWire(json['category'] as String?),
    );
  }
}

/// How a completed purchase was paid.
enum PaymentMethod { cash, bankTransfer, card, other }

extension PaymentMethodNaming on PaymentMethod {
  String get wireName => switch (this) {
        PaymentMethod.cash => 'cash',
        PaymentMethod.bankTransfer => 'bank_transfer',
        PaymentMethod.card => 'card',
        PaymentMethod.other => 'other',
      };

  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.bankTransfer => 'Bank transfer',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}

/// Body for `POST /expenses/{id}/complete-purchase`.
///
/// This is the step that actually moves stock — approval alone must not.
/// Every asset line appears exactly once, no consumable or foreign lines,
/// the full paid amount equals the expense total, and neither date may be
/// in the future.
class PurchaseCompletionInput {
  PurchaseCompletionInput({
    required this.paidOn,
    required this.receivedOn,
    required this.paidAmount,
    required this.paymentMethod,
    required this.paymentReference,
    required this.vendor,
    required this.items,
  });

  final DateTime paidOn;
  final DateTime receivedOn;

  /// Decimal string; must equal the expense amount.
  final String paidAmount;

  final PaymentMethod paymentMethod;
  final String paymentReference;
  final String vendor;
  final List<PurchaseLineConfirmation> items;

  static String _date(DateTime value) =>
      value.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() => {
        'paid_on': _date(paidOn),
        'received_on': _date(receivedOn),
        'paid_amount': paidAmount,
        'payment_method': paymentMethod.wireName,
        'payment_reference': paymentReference,
        'vendor': vendor,
        'items': [for (final item in items) item.toJson()],
      };
}

/// Image types the receipt endpoints accept, mapped from file extension to
/// the media type the backend validates against.
///
/// The backend checks the multipart part's `content_type` against this exact
/// set and does not look at the filename, so the mapping has to be right —
/// an unrecognized extension must be rejected here rather than sent as
/// `application/octet-stream` and refused with a confusing message.
const Map<String, String> receiptImageTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};

/// The media type for [filename], or null when the extension isn't one the
/// receipt endpoints accept.
String? receiptContentTypeFor(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return null;
  return receiptImageTypes[filename.substring(dot + 1).toLowerCase()];
}

/// Checks a purchase completion before anything is sent.
///
/// Mirrors the backend's own rules so the user gets a usable message
/// instead of a 422. Returns null when everything is acceptable, otherwise
/// the first problem found — in the order the form presents its fields, so
/// the message always points at something visible.
String? purchaseCompletionProblem({
  required List<ExpenseLine> assetLines,
  required DateTime? paidOn,
  required DateTime? receivedOn,
  required String rawPaidAmount,
  required double expenseTotal,
  required String reference,
  required String vendor,
  required Map<String, String> quantities,
  required Map<String, String> units,
  DateTime? today,
}) {
  if (assetLines.isEmpty) {
    return 'This expense has no asset lines, so there is nothing to stock.';
  }
  if (paidOn == null) return 'Choose the date this was paid.';
  if (receivedOn == null) return 'Choose the date this was received.';

  final now = today ?? DateTime.now();
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  if (paidOn.isAfter(endOfToday) || receivedOn.isAfter(endOfToday)) {
    return 'Payment and delivery dates cannot be in the future.';
  }

  final amountProblem = MoneyInput.validate(rawPaidAmount);
  if (amountProblem != null) return amountProblem;

  // The full amount must be paid — partial payment is not a completion.
  final paid = double.parse(rawPaidAmount.trim());
  if ((paid - expenseTotal).abs() >= 0.01) {
    return 'The paid amount must equal the expense total of '
        '₱${expenseTotal.toStringAsFixed(2)}.';
  }

  if (reference.trim().isEmpty) return 'Enter a payment reference.';
  if (vendor.trim().isEmpty) return 'Enter the supplier.';

  for (final line in assetLines) {
    final quantity = int.tryParse(quantities[line.id]?.trim() ?? '');
    if (quantity == null || quantity <= 0) {
      return 'Enter the quantity received for “${line.name}”.';
    }
    if ((units[line.id] ?? '').trim().isEmpty) {
      return 'Enter a unit for “${line.name}”.';
    }
  }

  return null;
}

class PurchaseLineConfirmation {
  PurchaseLineConfirmation({
    required this.expenseItemId,
    required this.quantity,
    required this.unit,
  });

  final String expenseItemId;

  /// The quantity actually received, which may differ from what was
  /// ordered. Must be greater than zero.
  final int quantity;

  final String unit;

  Map<String, dynamic> toJson() => {
        'expense_item_id': expenseItemId,
        'quantity': quantity,
        'unit': unit,
      };
}
