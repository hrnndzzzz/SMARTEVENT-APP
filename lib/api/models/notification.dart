/// A notification addressed to the signed-in user — `NotificationOut`.
///
/// These belong to one account: the list endpoint filters by the caller, so
/// there is no cross-user inbox and no way to mark someone else's as read.
///
/// The backend raises these for registration confirmations and, since
/// 24 Oct, for every SAP workflow step — submitted, returned, signed,
/// approved, evaluated, withdrawn, and each signature checkpoint. Those
/// carry a [payload] naming the event they are about.
///
/// Still do not promise device delivery, mark-all-read or deletion —
/// none of those exist.
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

  /// Small flat map the server attaches to workflow notices, so a notice
  /// can be opened rather than only read. Empty on anything older, and
  /// on kinds that do not set one — never assume a key is there.
  final Map<String, Object> payload;

  AppNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.readAt,
    required this.emailStatus,
    required this.createdAt,
    this.payload = const {},
  });

  bool get isUnread => readAt == null;

  /// The email could not be delivered. Worth showing next to the notice,
  /// since the user may be waiting for one that will never arrive.
  bool get emailFailed => emailStatus == 'failed';

  /// The event this notice is about, when it says. Null means the notice
  /// is not openable — a registration confirmation, or one raised before
  /// payloads existed — not that the event is missing.
  String? get eventId {
    final found = payload['event_id'];
    return found is String && found.isNotEmpty ? found : null;
  }

  /// The same notice, read. Used where there is no server to tell —
  /// the offline demo — so the list behaves the way it would online.
  AppNotice markedRead() => AppNotice(
    id: id,
    kind: kind,
    title: title,
    body: body,
    readAt: readAt ?? DateTime.now(),
    emailStatus: emailStatus,
    createdAt: createdAt,
    payload: payload,
  );

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
      // Declared as a string-or-int map, and null on older rows.
      payload: switch (json['payload']) {
        final Map<Object?, Object?> map => {
          for (final entry in map.entries)
            if (entry.key is String && entry.value != null)
              entry.key as String: entry.value!,
        },
        _ => const {},
      },
    );
  }
}
