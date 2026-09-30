import 'academic.dart';

/// Matches the backend's EventOut schema (see
/// `smartevent-backend/app/schemas.py`).
///
/// The academic fields — school year, semester and scope — arrived with the
/// September 2026 revision and are what make events reportable by year,
/// semester and department. They are parsed leniently so the app still runs
/// against an older backend that doesn't send them: missing simply reads as
/// "not set", which is also how genuinely incomplete legacy rows appear.
class RemoteEvent {
  final String id;
  final String? categoryId;
  final String title;
  final String? description;
  final String proposedBy;

  /// "draft" | "pending" (legacy, means awaiting adviser) |
  /// "pending_adviser" | "pending_admin" | "approved" | "rejected" |
  /// "completed".
  final String status;

  final DateTime? eventDate;
  final double estimatedCost;
  final double allocatedBudget;
  final double remainingBudget;

  /// Two consecutive years, e.g. `2026-2027`. Null on legacy rows that
  /// predate the requirement; an Admin repairs those through
  /// `PATCH /events/{id}/academic-metadata`.
  final String? schoolYear;

  final Semester? semester;
  final EventScope? eventScope;

  final String? departmentId;
  final String? organizationId;

  final DateTime createdAt;
  final DateTime updatedAt;

  RemoteEvent({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.proposedBy,
    required this.status,
    required this.eventDate,
    required this.estimatedCost,
    required this.allocatedBudget,
    required this.remainingBudget,
    required this.schoolYear,
    required this.semester,
    required this.eventScope,
    required this.departmentId,
    required this.organizationId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True when the row is missing any academic field, which is what the
  /// `missing_school_year` filter and the repair flow are for.
  bool get hasIncompleteAcademicMetadata =>
      schoolYear == null || semester == null || eventScope == null;

  factory RemoteEvent.fromJson(Map<String, dynamic> json) {
    return RemoteEvent(
      id: json['id'] as String,
      categoryId: json['category_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      proposedBy: json['proposed_by'] as String,
      status: json['status'] as String,
      eventDate: json['event_date'] == null ? null : DateTime.parse(json['event_date'] as String),
      estimatedCost: (json['estimated_cost'] as num).toDouble(),
      allocatedBudget: (json['allocated_budget'] as num).toDouble(),
      remainingBudget: (json['remaining_budget'] as num).toDouble(),
      schoolYear: json['school_year'] as String?,
      semester: semesterFromWire(json['semester'] as String?),
      eventScope: eventScopeFromWire(json['event_scope'] as String?),
      departmentId: json['department_id'] as String?,
      organizationId: json['organization_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Matches ApprovalOut exactly — one row in an event's (or expense's)
/// review timeline.
class ApprovalRecord {
  final String id;
  final String entityType;
  final String entityId;
  final int stepOrder;
  final String? reviewerId;
  final String decision;
  final String? remarks;
  final DateTime? decidedAt;

  ApprovalRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.stepOrder,
    required this.reviewerId,
    required this.decision,
    required this.remarks,
    required this.decidedAt,
  });

  factory ApprovalRecord.fromJson(Map<String, dynamic> json) {
    return ApprovalRecord(
      id: json['id'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      stepOrder: json['step_order'] as int,
      reviewerId: json['reviewer_id'] as String?,
      decision: json['decision'] as String,
      remarks: json['remarks'] as String?,
      decidedAt: json['decided_at'] == null ? null : DateTime.parse(json['decided_at'] as String),
    );
  }
}