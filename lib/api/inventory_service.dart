import 'api_client.dart';
import 'models/inventory.dart';

/// The inventory catalog and its stock ledger.
///
/// Quantity is deliberately absent from [update]: stock only moves through
/// [recordMovement] or through completing a purchase, so every change has a
/// row saying why.
class InventoryService {
  final ApiClient _client;
  InventoryService(this._client);

  /// `GET /inventory`.
  ///
  /// [isDraft], [eventId] and [missingEvent] are real server-side filters.
  /// Event filtering matches both the item's own event and any event it has
  /// been moved for.
  Future<List<RemoteInventoryItem>> list({
    bool? isDraft,
    String? eventId,
    bool missingEvent = false,
  }) async {
    final query = <String, String>{
      if (isDraft != null) 'is_draft': isDraft.toString(),
      if (eventId != null) 'event_id': eventId,
      if (missingEvent) 'missing_event': 'true',
    };
    final response = await _client.get(
      '/inventory',
      query: query.isEmpty ? null : query,
    );
    return (response as List)
        .map((json) => RemoteInventoryItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `GET /inventory/low-stock` — at or below each item's own threshold.
  Future<List<RemoteInventoryItem>> lowStock() async {
    final response = await _client.get('/inventory/low-stock');
    return (response as List)
        .map((json) => RemoteInventoryItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteInventoryItem> get(String inventoryId) async {
    final response = await _client.get('/inventory/$inventoryId');
    return RemoteInventoryItem.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /inventory` — Admin/Super Admin.
  ///
  /// A positive [quantity] writes an opening ledger entry of
  /// [initialTransactionType]. Newly bought goods must **not** be recorded
  /// as opening stock: that would bypass payment completion and lose the
  /// link to the expense that paid for them.
  Future<RemoteInventoryItem> create({
    required String eventId,
    required String itemName,
    String? description,
    int quantity = 0,
    String unit = 'pcs',
    int lowStockThreshold = 5,
    String? location,
    InitialStockType initialTransactionType = InitialStockType.openingBalance,
    String reason = 'Opening stock',
    String? departmentId,
    String? organizationId,
  }) async {
    final response = await _client.post('/inventory', body: {
      'event_id': eventId,
      'item_name': itemName,
      if (description != null) 'description': description,
      'quantity': quantity,
      'unit': unit,
      'low_stock_threshold': lowStockThreshold,
      if (location != null) 'location': location,
      'initial_transaction_type': initialTransactionType.wireName,
      'reason': reason,
      if (departmentId != null) 'department_id': departmentId,
      if (organizationId != null) 'organization_id': organizationId,
    });
    return RemoteInventoryItem.fromJson(response as Map<String, dynamic>);
  }

  /// `PATCH /inventory/{id}` — metadata only, Admin/Super Admin.
  ///
  /// There is no quantity parameter and there should not be. [eventId] can
  /// fill in a missing legacy link but cannot replace an existing one: to
  /// use an item at another event, record a movement instead. A unit change
  /// may be refused once stock or history exists.
  Future<RemoteInventoryItem> update(
    String inventoryId, {
    String? itemName,
    String? description,
    String? unit,
    int? lowStockThreshold,
    String? location,
    String? eventId,
  }) async {
    final response = await _client.patch('/inventory/$inventoryId', body: {
      if (itemName != null) 'item_name': itemName,
      if (description != null) 'description': description,
      if (unit != null) 'unit': unit,
      if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
      if (location != null) 'location': location,
      if (eventId != null) 'event_id': eventId,
    });
    return RemoteInventoryItem.fromJson(response as Map<String, dynamic>);
  }

  /// Admin/Super Admin, and only for an item with zero stock and no
  /// transaction or purchase provenance.
  Future<void> delete(String inventoryId) async {
    await _client.delete('/inventory/$inventoryId');
  }

  /// `POST /inventory/{id}/confirm-draft` — accepts a catalog record that
  /// purchase completion created.
  ///
  /// This does **not** increment quantity. The stock was already added when
  /// the purchase was completed; confirming only makes the record usable
  /// for manual movements.
  Future<RemoteInventoryItem> confirmDraft(String inventoryId) async {
    final response = await _client.post('/inventory/$inventoryId/confirm-draft');
    return RemoteInventoryItem.fromJson(response as Map<String, dynamic>);
  }

  Future<List<InventoryMovement>> movements(
    String inventoryId, {
    String? eventId,
  }) async {
    final response = await _client.get(
      '/inventory/$inventoryId/transactions',
      query: eventId == null ? null : {'event_id': eventId},
    );
    return (response as List)
        .map((json) => InventoryMovement.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `POST /inventory/{id}/transactions` — the only way stock moves by hand.
  ///
  /// [changeQty] is signed and must not be zero; use `signedChangeFor` to
  /// derive it from a positive count. A `purchase` type is refused with a
  /// 409 — that comes from completing an expense. Stock may never go
  /// negative, and a return may not exceed what is still out for that event.
  Future<InventoryMovement> recordMovement(
    String inventoryId, {
    required InventoryMovementType type,
    required String eventId,
    required int changeQty,
    required String reason,
  }) async {
    final response = await _client.post(
      '/inventory/$inventoryId/transactions',
      body: {
        'transaction_type': type.wireName,
        'event_id': eventId,
        'change_qty': changeQty,
        'reason': reason,
      },
    );
    return InventoryMovement.fromJson(response as Map<String, dynamic>);
  }

  /// Admin/Super Admin repair for incomplete legacy movements.
  ///
  /// Fills in missing metadata only. It cannot replay a movement or change
  /// any historical quantity, so it can't be used to rewrite stock history.
  Future<InventoryMovement> repairMovement(
    String inventoryId,
    String movementId, {
    required String eventId,
    required InventoryMovementType type,
    required String reason,
  }) async {
    final response = await _client.patch(
      '/inventory/$inventoryId/transactions/$movementId/metadata',
      body: {
        'event_id': eventId,
        'transaction_type': type.wireName,
        'reason': reason,
      },
    );
    return InventoryMovement.fromJson(response as Map<String, dynamic>);
  }

  /// The backend's cap on a movement reason.
  static const int maxReasonLength = 100;
}
