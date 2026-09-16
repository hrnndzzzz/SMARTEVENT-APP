import 'api_client.dart';
import 'models/remote_event.dart';

class EventService {
  final ApiClient _client;
  EventService(this._client);

  Future<List<RemoteEvent>> list() async {
    final response = await _client.get('/events');
    return (response as List).map((json) => RemoteEvent.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<RemoteEvent> get(String eventId) async {
    final response = await _client.get('/events/$eventId');
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  Future<List<ApprovalRecord>> listApprovals(String eventId) async {
    final response = await _client.get('/events/$eventId/approvals');
    return (response as List).map((json) => ApprovalRecord.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// [status] must be "draft" or "pending" — the backend's own logic
  /// (matching our creator-skip rule) decides which real stage
  /// "pending" actually resolves to based on who's creating it.
  Future<RemoteEvent> create({
    String? categoryId,
    required String title,
    String? description,
    DateTime? eventDate,
    double estimatedCost = 0,
    double allocatedBudget = 0,
    String status = 'draft',
  }) async {
    final response = await _client.post('/events', body: {
      if (categoryId != null) 'category_id': categoryId,
      'title': title,
      if (description != null) 'description': description,
      if (eventDate != null) 'event_date': eventDate.toIso8601String().split('T').first,
      'estimated_cost': estimatedCost,
      'allocated_budget': allocatedBudget,
      'status': status,
    });
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  /// PATCH semantics — only pass fields you want to change. Only
  /// works while the event is draft or rejected (backend-enforced).
  Future<RemoteEvent> update(
      String eventId, {
        String? categoryId,
        String? title,
        String? description,
        DateTime? eventDate,
        double? estimatedCost,
        double? allocatedBudget,
      }) async {
    final body = <String, dynamic>{
      if (categoryId != null) 'category_id': categoryId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (eventDate != null) 'event_date': eventDate.toIso8601String().split('T').first,
      if (estimatedCost != null) 'estimated_cost': estimatedCost,
      if (allocatedBudget != null) 'allocated_budget': allocatedBudget,
    };
    final response = await _client.patch('/events/$eventId', body: body);
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  /// Moves draft->pending or resubmits rejected->pending, landing on
  /// the correct stage automatically based on who's submitting.
  Future<RemoteEvent> submit(String eventId) async {
    final response = await _client.post('/events/$eventId/submit');
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  Future<RemoteEvent> approve(String eventId, {String? remarks}) async {
    final response = await _client.post('/events/$eventId/approve', body: {
      if (remarks != null) 'remarks': remarks,
    });
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  Future<RemoteEvent> reject(String eventId, {String? remarks}) async {
    final response = await _client.post('/events/$eventId/reject', body: {
      if (remarks != null) 'remarks': remarks,
    });
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  /// Only draft events can be deleted (backend-enforced).
  Future<void> delete(String eventId) async {
    await _client.delete('/events/$eventId');
  }
}