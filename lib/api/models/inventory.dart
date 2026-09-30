/// A catalog item and its stock — the backend's `InventoryOut`.
///
/// `Remote*` because `InventoryItem` is already a local display model in
/// `app_state.dart`.
///
/// The rule that shapes this whole module: **quantity is never written
/// directly**. There is no quantity field on the update endpoint. Stock only
/// moves through a transaction, so every change has a row explaining why —
/// the same pattern as a category's remaining budget only moving when an
/// expense is approved.
class RemoteInventoryItem {
  final String id;
  final String itemName;
  final String? description;

  /// Read-only here. Changed only by recording a movement.
  final int quantity;

  final String unit;
  final int lowStockThreshold;
  final String? location;

  /// Created automatically by purchase completion and not yet confirmed by
  /// an administrator. A draft cannot take manual movements until it is
  /// confirmed — and confirming does not add stock.
  final bool isDraft;

  /// The event this belongs to. Legacy rows may have none, which is what
  /// the `missing_event` filter and the repair flow are for.
  final String? eventId;

  final String? departmentId;
  final String? organizationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  RemoteInventoryItem({
    required this.id,
    required this.itemName,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.lowStockThreshold,
    required this.location,
    required this.isDraft,
    required this.eventId,
    required this.departmentId,
    required this.organizationId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLowStock => quantity <= lowStockThreshold;

  /// Stock is zero, so it may be deletable — the backend still refuses if
  /// it has any transaction or purchase provenance.
  bool get isEmpty => quantity == 0;

  /// A legacy row with no event, which keeps it out of event-filtered
  /// reporting until an administrator repairs it.
  bool get needsEventLink => eventId == null;

  /// Usable for ordinary movements: confirmed, and linked to an event.
  bool get isUsable => !isDraft && eventId != null;

  factory RemoteInventoryItem.fromJson(Map<String, dynamic> json) {
    return RemoteInventoryItem(
      id: json['id'] as String,
      itemName: json['item_name'] as String,
      description: json['description'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      unit: json['unit'] as String? ?? 'pcs',
      lowStockThreshold: (json['low_stock_threshold'] as num?)?.toInt() ?? 0,
      location: json['location'] as String?,
      isDraft: json['is_draft'] as bool? ?? false,
      eventId: json['event_id'] as String?,
      departmentId: json['department_id'] as String?,
      organizationId: json['organization_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// One movement in the stock ledger — `InventoryTransactionOut`.
class InventoryMovement {
  final String id;
  final String inventoryId;
  final String? eventId;

  /// Signed: positive is stock arriving, negative is stock leaving. Never
  /// zero — a movement of nothing is not a movement.
  final int changeQty;

  final InventoryMovementType type;
  final String? reason;
  final String performedBy;

  /// Set when this movement came from completing a purchase, linking the
  /// stock back to the expense line that paid for it.
  final String? expenseItemId;

  final DateTime createdAt;

  InventoryMovement({
    required this.id,
    required this.inventoryId,
    required this.eventId,
    required this.changeQty,
    required this.type,
    required this.reason,
    required this.performedBy,
    required this.expenseItemId,
    required this.createdAt,
  });

  bool get isIncoming => changeQty > 0;

  /// Came from a completed purchase rather than being recorded by hand.
  bool get isFromPurchase => expenseItemId != null;

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    return InventoryMovement(
      id: json['id'] as String,
      inventoryId: json['inventory_id'] as String,
      eventId: json['event_id'] as String?,
      changeQty: (json['change_qty'] as num).toInt(),
      type: inventoryMovementTypeFromWire(json['transaction_type'] as String?),
      reason: json['reason'] as String?,
      performedBy: json['performed_by'] as String,
      expenseItemId: json['expense_item_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Every movement type the backend recognises.
///
/// Not all are things a user picks. `purchase` is produced only by
/// completing an expense — recording one by hand is refused with a 409.
/// `openingBalance` happens once at creation, and `legacy` is what
/// unclassified historical rows read as.
enum InventoryMovementType {
  openingBalance,
  acquisition,
  donation,
  purchase,
  issue,
  returned,
  disposal,
  adjustment,
  legacy,
}

extension InventoryMovementTypeInfo on InventoryMovementType {
  String get wireName => switch (this) {
        InventoryMovementType.openingBalance => 'opening_balance',
        InventoryMovementType.acquisition => 'acquisition',
        InventoryMovementType.donation => 'donation',
        InventoryMovementType.purchase => 'purchase',
        InventoryMovementType.issue => 'issue',
        // 'return' is a Dart keyword, hence the enum name.
        InventoryMovementType.returned => 'return',
        InventoryMovementType.disposal => 'disposal',
        InventoryMovementType.adjustment => 'adjustment',
        InventoryMovementType.legacy => 'legacy',
      };

  /// What a person would call it.
  String get label => switch (this) {
        InventoryMovementType.openingBalance => 'Opening balance',
        InventoryMovementType.acquisition => 'Acquired',
        InventoryMovementType.donation => 'Donated',
        InventoryMovementType.purchase => 'Purchased',
        InventoryMovementType.issue => 'Issued for an event',
        InventoryMovementType.returned => 'Returned from an event',
        InventoryMovementType.disposal => 'Disposed',
        InventoryMovementType.adjustment => 'Adjustment',
        InventoryMovementType.legacy => 'Legacy record',
      };

  /// The direction the backend enforces. Null means either is allowed.
  bool? get mustBePositive => switch (this) {
        InventoryMovementType.acquisition ||
        InventoryMovementType.donation ||
        InventoryMovementType.purchase ||
        InventoryMovementType.returned =>
          true,
        InventoryMovementType.issue || InventoryMovementType.disposal => false,
        _ => null,
      };

  /// Whether a user may choose this when recording a movement.
  ///
  /// Purchases come from completing an expense, an opening balance is set
  /// once at creation, and `legacy` is a state rather than an action.
  bool get isUserSelectable => switch (this) {
        InventoryMovementType.acquisition ||
        InventoryMovementType.donation ||
        InventoryMovementType.issue ||
        InventoryMovementType.returned ||
        InventoryMovementType.disposal ||
        InventoryMovementType.adjustment =>
          true,
        _ => false,
      };

  String get hint => switch (this) {
        InventoryMovementType.acquisition =>
          'Obtained without a purchase record.',
        InventoryMovementType.donation => 'Given to the organization.',
        InventoryMovementType.issue => 'Taken out for use at an event.',
        InventoryMovementType.returned =>
          'Brought back. Cannot exceed what is still out for that event.',
        InventoryMovementType.disposal => 'Damaged, lost or written off.',
        InventoryMovementType.adjustment =>
          'A documented correction, up or down.',
        InventoryMovementType.purchase =>
          'Recorded by completing the paying expense, not by hand.',
        InventoryMovementType.openingBalance =>
          'Set once, when the item is created.',
        InventoryMovementType.legacy => 'An unclassified historical record.',
      };
}

/// Types a user may pick in the movement form.
List<InventoryMovementType> get selectableMovementTypes =>
    InventoryMovementType.values.where((t) => t.isUserSelectable).toList();

/// Unknown values read as [InventoryMovementType.legacy], which is also
/// what the backend calls an unclassified historical row.
InventoryMovementType inventoryMovementTypeFromWire(String? value) =>
    switch (value) {
      'opening_balance' => InventoryMovementType.openingBalance,
      'acquisition' => InventoryMovementType.acquisition,
      'donation' => InventoryMovementType.donation,
      'purchase' => InventoryMovementType.purchase,
      'issue' => InventoryMovementType.issue,
      'return' => InventoryMovementType.returned,
      'disposal' => InventoryMovementType.disposal,
      'adjustment' => InventoryMovementType.adjustment,
      _ => InventoryMovementType.legacy,
    };

/// The transaction type an item starts with. Only these three are accepted
/// at creation — a new item cannot start life as a purchase.
enum InitialStockType { openingBalance, acquisition, donation }

extension InitialStockTypeNaming on InitialStockType {
  String get wireName => switch (this) {
        InitialStockType.openingBalance => 'opening_balance',
        InitialStockType.acquisition => 'acquisition',
        InitialStockType.donation => 'donation',
      };

  String get label => switch (this) {
        InitialStockType.openingBalance => 'Opening balance',
        InitialStockType.acquisition => 'Acquired',
        InitialStockType.donation => 'Donated',
      };
}

/// Turns the count a user types into the signed change the API expects.
///
/// Forms ask for a positive count even for Issue and Disposal, because
/// "issue 5" is how people think — the sign is applied here, deliberately,
/// rather than asking anyone to type a minus.
///
/// Returns null when [count] is not a usable whole number.
int? signedChangeFor(InventoryMovementType type, String count) {
  final value = int.tryParse(count.trim());
  if (value == null || value == 0) return null;

  final magnitude = value.abs();
  return switch (type.mustBePositive) {
    true => magnitude,
    false => -magnitude,
    // An adjustment is the one place a direction is genuinely the user's
    // to choose, so the sign they typed is respected.
    _ => value,
  };
}
