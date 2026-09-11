import 'api_client.dart';
import 'models/category.dart';

class CategoryService {
  final ApiClient _client;
  CategoryService(this._client);

  Future<List<Category>> list() async {
    final response = await _client.get('/categories');
    return (response as List).map((json) => Category.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<Category> get(String categoryId) async {
    final response = await _client.get('/categories/$categoryId');
    return Category.fromJson(response as Map<String, dynamic>);
  }

  Future<Category> create({
    required String name,
    required double allocatedBudget,
    double lowBalanceThreshold = 0,
  }) async {
    final response = await _client.post('/categories', body: {
      'name': name,
      'allocated_budget': allocatedBudget,
      'low_balance_threshold': lowBalanceThreshold,
    });
    return Category.fromJson(response as Map<String, dynamic>);
  }

  Future<Category> update(
      String categoryId, {
        String? name,
        double? allocatedBudget,
        double? lowBalanceThreshold,
      }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (allocatedBudget != null) 'allocated_budget': allocatedBudget,
      if (lowBalanceThreshold != null) 'low_balance_threshold': lowBalanceThreshold,
    };
    final response = await _client.patch('/categories/$categoryId', body: body);
    return Category.fromJson(response as Map<String, dynamic>);
  }

  Future<void> delete(String categoryId) async {
    await _client.delete('/categories/$categoryId');
  }
}