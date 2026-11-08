import 'api_client.dart';

/// Who last changed something in proposals, inventory or finance.
class ActivityNote {
  const ActivityNote({
    required this.action,
    required this.actorName,
    required this.createdAt,
    required this.subject,
  });

  /// The audit action, e.g. `inventory.deleted` or `sap_submitted`.
  final String action;
  final String actorName;
  final DateTime createdAt;

  /// What it was done to, by name. Kept with the entry when the record
  /// itself is gone.
  final String? subject;

  factory ActivityNote.fromJson(Map<String, dynamic> json) => ActivityNote(
    action: json['action'] as String,
    actorName: json['actor_name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    subject: json['subject'] as String?,
  );

  /// "Maria Santos removed Batteries".
  String get sentence => [
    actorName,
    activityVerb(action),
    if (subject case final subject? when subject.isNotEmpty) subject,
  ].join(' ');
}

/// The audit action in plain words.
String activityVerb(String action) {
  const exact = {
    'inventory.movement_recorded': 'recorded a stock movement on',
    'income.recorded': 'recorded income from',
    'purchase.completed': 'completed the purchase for',
    'receipt.file_uploaded': 'attached a receipt to',
    'sap_attachment_uploaded': 'attached a file to',
    'sap_approved_with_physical_evidence': 'approved',
    'sap_checkpoint_recorded': 'recorded a checkpoint on',
    'sap_review_notes_saved': 'saved review notes on',
    'sap_signed_revision_correction_requested': 'asked for corrections to',
  };
  if (exact[action] case final verb?) return verb;
  final word = action.split(RegExp(r'[._]')).last;
  return switch (word) {
    'created' || 'recorded' => 'added',
    'updated' || 'replaced' => 'edited',
    'deleted' || 'archived' => 'removed',
    _ => word,
  };
}

class ActivityService {
  ActivityService(this._client);

  final ApiClient _client;

  /// `GET /audit-logs/latest` — [area] is `proposals`, `inventory` or
  /// `finance`; [entityId] narrows it to one record. Null when nothing has
  /// been recorded yet.
  Future<ActivityNote?> latest(String area, {String? entityId}) async {
    final response = await _client.get(
      '/audit-logs/latest',
      query: {'area': area, if (entityId != null) 'entity_id': entityId},
    );
    return response == null
        ? null
        : ActivityNote.fromJson((response as Map).cast<String, dynamic>());
  }
}
