import 'api_client.dart';
import 'models/scope.dart';

/// Department and organization lookups.
///
/// Both endpoints require Admin or above, and a non-Super-Admin sees only
/// its own. Ordinary operational forms must never call these — a Treasurer
/// or Officer would just collect a 403. They exist for the one case where
/// scope genuinely has to be chosen: a Super Admin, who belongs to none.
class ScopeService {
  final ApiClient _client;
  ScopeService(this._client);

  Future<List<RemoteDepartment>> departments() async {
    final response = await _client.get('/departments');
    return (response as List)
        .map((json) => RemoteDepartment.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<RemoteOrganization>> organizations() async {
    final response = await _client.get('/organizations');
    return (response as List)
        .map((json) => RemoteOrganization.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
