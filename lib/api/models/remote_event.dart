/// Matches the backend's EventOut schema exactly (see
/// smartevent-backend/app/schemas.py). Status now includes
/// pending_adviser/pending_admin after the two-stage approval patch
/// we wrote and Jasper merged — real backend and local UI finally
/// agree on the same workflow.
class RemoteEvent {
  final String id;
  final String? categoryId;
  final String title;
  final String? description;
  final String proposedBy;
  final String status; // "draft" | "pending_adviser" | "pending_admin" | "approved" | "rejected" | "completed"
  final DateTime? eventDate;
  final double estimatedCost;
  final double allocatedBudget;
  final double remainingBudget;
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
    required this.createdAt,
    required this.updatedAt,
  });

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