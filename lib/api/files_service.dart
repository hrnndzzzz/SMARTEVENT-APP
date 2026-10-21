import 'api_client.dart';

/// Reaching a stored file.
///
/// A receipt or a proposal is kept in Supabase storage and the record
/// holds a reference to it. Whether that reference can be opened directly
/// depends on the backend: while the buckets are public it is already a
/// URL, and once they are private it has to be exchanged for a signed one
/// that lasts five minutes.
///
/// [resolve] handles both, so a screen can show a stored image without
/// knowing which backend it is talking to. On a deployment with no
/// `/files` route the reference comes straight back, which is exactly
/// right there.
class FilesService {
  FilesService(this._client);

  final ApiClient _client;

  Future<String> resolve(String reference) async {
    try {
      final response = await _client.get(
        '/files',
        query: {'reference': reference},
      );
      if (response is Map && response['url'] is String) {
        return response['url'] as String;
      }
    } catch (_) {
      // No such route, or it refused. The reference is the best we have,
      // and on a public bucket it loads.
    }
    return reference;
  }
}
