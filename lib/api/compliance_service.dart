import 'api_client.dart';
import 'models/compliance.dart';

/// Raised when the deployment this build is talking to has no
/// institutional-approval routes.
///
/// The app targets a backend that may or may not have been upgraded yet,
/// and a screen that silently shows nothing is worse than one that says
/// which half of the system is behind. Callers surface this as a notice
/// rather than as an error.
class FeatureUnavailable implements Exception {
  const FeatureUnavailable();
}

/// The pre-activity gates: logistics and readiness.
class ComplianceService {
  ComplianceService(this._client);

  final ApiClient _client;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (error) {
      if (error.statusCode == 404) throw const FeatureUnavailable();
      rethrow;
    }
  }

  /// `GET /events/{id}/logistics` — null when nothing has been saved yet,
  /// which is itself the first readiness blocker.
  Future<EventLogistics?> logistics(String eventId) {
    return _guard(() async {
      final response = await _client.get('/events/$eventId/logistics');
      final row = (response as Map)['logistics'];
      return row == null
          ? null
          : EventLogistics.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  /// `PUT /events/{id}/logistics`.
  ///
  /// Changing the location, destination or transport mode clears any
  /// verification already done — the backend says so and keeps the
  /// files, so the screen warns before saving rather than after.
  Future<EventLogistics?> saveLogistics(
    String eventId,
    EventLogistics logistics,
  ) {
    return _guard(() async {
      final response = await _client.put(
        '/events/$eventId/logistics',
        body: logistics.toJson(),
      );
      final row = (response as Map)['logistics'];
      return row == null
          ? null
          : EventLogistics.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  /// `GET /events/{id}/readiness`.
  Future<EventReadiness> readiness(String eventId) {
    return _guard(() async {
      final response = await _client.get('/events/$eventId/readiness');
      return EventReadiness.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    });
  }
}
