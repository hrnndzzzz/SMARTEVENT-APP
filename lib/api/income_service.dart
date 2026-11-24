import 'api_client.dart';
import 'models/income.dart';
import 'models/remote_expense.dart' show ReceiptDetailsInput;

/// Income against events.
///
/// The API is deliberately small: record and list, nothing else. There is
/// no single-income GET, so a detail view uses the row already loaded; and
/// there is **no edit or delete**, so the app must not offer either.
class IncomeService {
  final ApiClient _client;
  IncomeService(this._client);

  /// `GET /incomes`, optionally narrowed to one event. The whole list
  /// includes general-fund income, which the server sends only on request.
  Future<List<Income>> list({String? eventId}) async {
    final response = await _client.get(
      '/incomes',
      query: eventId == null
          ? {'include_general': 'true'}
          : {'event_id': eventId},
    );
    return (response as List)
        .map((json) => Income.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `POST /incomes` — Officer or Super Admin. There is no
  /// approval step for income; it counts once recorded, unless its receipt
  /// is held for review.
  ///
  /// [amount] is a decimal string and must be positive. An [receipt] may be
  /// attached inline, and its URL must already exist — there is no
  /// file-first income creation route, and inventing a placeholder URL to
  /// work around that would corrupt the audit trail.
  ///
  /// With no [eventId] it is general-fund income, which needs [schoolYear]
  /// and [semester] (wire values) and cannot carry a receipt. A Super Admin,
  /// who has no organization of its own, also names one with [organizationId].
  Future<Income> record({
    required String? eventId,
    required String source,
    required FundSource sourceType,
    required String purpose,
    required String amount,
    DateTime? receivedOn,
    ReceiptDetailsInput? receipt,
    String? schoolYear,
    String? semester,
    String? organizationId,
  }) async {
    final response = await _client.post(
      '/incomes',
      body: {
        'event_id': ?eventId,
        'school_year': ?schoolYear,
        'semester': ?semester,
        'organization_id': ?organizationId,
        'source': source,
        'source_type': sourceType.wireName,
        'purpose': purpose,
        'amount': amount,
        if (receivedOn != null)
          'received_on': receivedOn.toIso8601String().split('T').first,
        if (receipt != null) 'receipt': receipt.toJson(),
      },
    );
    return Income.fromJson(response as Map<String, dynamic>);
  }
}
