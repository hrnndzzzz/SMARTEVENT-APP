import 'api_client.dart';
import 'models/academic.dart';
import 'models/remote_event.dart';

class EventService {
  final ApiClient _client;
  EventService(this._client);

  /// `GET /events`.
  ///
  /// Only `school_year` and `missing_school_year` are real server-side
  /// filters. Status and text search are applied locally to what comes
  /// back — there is no general search or pagination API, and inventing
  /// query parameters the backend ignores would silently return everything.
  Future<List<RemoteEvent>> list({
    String? schoolYear,
    bool missingSchoolYear = false,
  }) async {
    final query = <String, String>{
      if (schoolYear != null) 'school_year': schoolYear,
      if (missingSchoolYear) 'missing_school_year': 'true',
    };
    final response = await _client.get(
      '/events',
      query: query.isEmpty ? null : query,
    );
    return (response as List)
        .map((json) => RemoteEvent.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `GET /events/school-years` — the years that already exist and are
  /// visible to this account.
  ///
  /// A create form must still accept a valid year that is not in this list,
  /// since the first event of a new school year has to start somewhere.
  /// The shape is read defensively: a bare list of strings and a list of
  /// objects carrying `school_year` both parse.
  Future<List<String>> schoolYears() async {
    final response = await _client.get('/events/school-years');
    if (response is! List) return const [];

    return response
        .map((entry) => switch (entry) {
              String value => value,
              Map entry when entry['school_year'] is String =>
                entry['school_year'] as String,
              _ => null,
            })
        .whereType<String>()
        .where(SchoolYear.isValid)
        .toList();
  }

  Future<RemoteEvent> get(String eventId) async {
    final response = await _client.get('/events/$eventId');
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  Future<List<ApprovalRecord>> listApprovals(String eventId) async {
    final response = await _client.get('/events/$eventId/approvals');
    return (response as List)
        .map((json) => ApprovalRecord.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `POST /events`.
  ///
  /// [status] must be `draft` or `pending` — never a final status. Which
  /// review stage `pending` lands on is the backend's decision, based on
  /// who is proposing: an Adviser's own proposal skips the adviser stage,
  /// everyone else's starts there. Nothing is ever auto-approved.
  ///
  /// School year, semester and scope are required by the current backend.
  /// Scoped accounts get their own department and organization applied
  /// server-side; a Super Admin supplies them explicitly.
  Future<RemoteEvent> create({
    String? categoryId,
    required String title,
    String? description,
    DateTime? eventDate,
    double estimatedCost = 0,
    double allocatedBudget = 0,
    String status = 'draft',
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
    String? departmentId,
    String? organizationId,
  }) async {
    final response = await _client.post('/events', body: {
      if (categoryId != null) 'category_id': categoryId,
      'title': title,
      if (description != null) 'description': description,
      if (eventDate != null) 'event_date': _asDate(eventDate),
      'estimated_cost': estimatedCost,
      'allocated_budget': allocatedBudget,
      'status': status,
      if (schoolYear != null) 'school_year': schoolYear,
      if (semester != null) 'semester': semester.wireName,
      if (eventScope != null) 'event_scope': eventScope.wireName,
      if (departmentId != null) 'department_id': departmentId,
      if (organizationId != null) 'organization_id': organizationId,
    });
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  /// PATCH semantics — pass only what changed. Omitted fields are left
  /// alone; sending null would be read as clearing them.
  ///
  /// Accepted only while the event is draft or rejected (backend-enforced).
  Future<RemoteEvent> update(
    String eventId, {
    String? categoryId,
    String? title,
    String? description,
    DateTime? eventDate,
    double? estimatedCost,
    double? allocatedBudget,
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
  }) async {
    final body = <String, dynamic>{
      if (categoryId != null) 'category_id': categoryId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (eventDate != null) 'event_date': _asDate(eventDate),
      if (estimatedCost != null) 'estimated_cost': estimatedCost,
      if (allocatedBudget != null) 'allocated_budget': allocatedBudget,
      if (schoolYear != null) 'school_year': schoolYear,
      if (semester != null) 'semester': semester.wireName,
      if (eventScope != null) 'event_scope': eventScope.wireName,
    };
    final response = await _client.patch('/events/$eventId', body: body);
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  /// `PATCH /events/{id}/academic-metadata` — Admin/Super Admin only.
  ///
  /// Fills in missing academic fields on legacy rows. It does not overwrite
  /// values that are already set, so this is a repair tool and not a second
  /// edit route; keep it in an administrator-only corner of the UI.
  Future<RemoteEvent> repairAcademicMetadata(
    String eventId, {
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
  }) async {
    final response = await _client.patch(
      '/events/$eventId/academic-metadata',
      body: {
        if (schoolYear != null) 'school_year': schoolYear,
        if (semester != null) 'semester': semester.wireName,
        if (eventScope != null) 'event_scope': eventScope.wireName,
      },
    );
    return RemoteEvent.fromJson(response as Map<String, dynamic>);
  }

  /// Moves draft -> pending, or resubmits rejected -> pending. The stage it
  /// lands on follows the original proposer, including when an
  /// administrator resubmits on someone else's behalf.
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

  /// Draft events only, and references may still prevent it.
  Future<void> delete(String eventId) async {
    await _client.delete('/events/$eventId');
  }

  /// Dates go over the wire as `YYYY-MM-DD`, never a full timestamp.
  static String _asDate(DateTime value) =>
      value.toIso8601String().split('T').first;
}
