/// Matches the backend's CategoryOut schema exactly (see
/// smartevent-backend/app/schemas.py). remaining_budget is
/// intentionally never client-settable — it only ever changes via the
/// database trigger (fn_deduct_category_balance) when an expense is
/// approved, so there's no "set remaining" method anywhere here.
class Category {
  final String id;
  final String name;
  final double allocatedBudget;
  final double remainingBudget;
  final double? lowBalanceThreshold;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category({
    required this.id,
    required this.name,
    required this.allocatedBudget,
    required this.remainingBudget,
    required this.lowBalanceThreshold,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      allocatedBudget: (json['allocated_budget'] as num).toDouble(),
      remainingBudget: (json['remaining_budget'] as num).toDouble(),
      lowBalanceThreshold: (json['low_balance_threshold'] as num?)?.toDouble(),
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}