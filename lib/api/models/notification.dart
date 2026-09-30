/// A notification addressed to the signed-in user — `NotificationOut`.
///
/// These belong to one account: the list endpoint filters by the caller, so
/// there is no cross-user inbox and no way to mark someone else's as read.
///
/// The backend currently raises these for registration confirmations only.
/// Do not promise event-approval pushes, device delivery, mark-all-read or
/// deletion — none of those exist.
class AppNotice {
  final String id;

  /// What kind of event produced it, as the backend names it.
  final String kind;

  final String title;
  final String body;

  /// Null while unread. The presence of a timestamp *is* the read state.
  final DateTime? readAt;

  /// 'pending' | 'sent' | 'failed' — whether the matching email went out.
  /// A failed email does not mean the notification itself failed.
  final String emailStatus;

  final DateTime createdAt;

  AppNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.readAt,
    required this.emailStatus,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  /// The email could not be delivered. Worth showing next to the notice,
  /// since the user may be waiting for one that will never arrive.
  bool get emailFailed => emailStatus == 'failed';

  factory AppNotice.fromJson(Map<String, dynamic> json) {
    return AppNotice(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'] as String),
      emailStatus: json['email_status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
