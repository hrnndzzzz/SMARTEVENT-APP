import 'api_client.dart';
import 'models/notification.dart';

/// The signed-in user's notification inbox.
///
/// Small on purpose: list, count, and mark one as read. There is no
/// mark-all-read and no delete, so the app offers neither.
class NotificationService {
  final ApiClient _client;
  NotificationService(this._client);

  Future<List<AppNotice>> list({
    bool unreadOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client.get('/notifications', query: {
      if (unreadOnly) 'unread_only': 'true',
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return (response as List)
        .map((json) => AppNotice.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Just the badge number, without pulling the whole inbox.
  Future<int> unreadCount() async {
    final response = await _client.get('/notifications/unread-count');
    return ((response as Map)['unread_count'] as num?)?.toInt() ?? 0;
  }

  /// Marks one of the caller's own notifications read. No payload needed —
  /// and there is no way to mark someone else's.
  Future<AppNotice> markRead(String notificationId) async {
    final response =
        await _client.patch('/notifications/$notificationId/read');
    return AppNotice.fromJson(response as Map<String, dynamic>);
  }
}
