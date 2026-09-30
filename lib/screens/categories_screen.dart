import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/models/category.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

/// Categories — full CRUD, which `FRONTEND_README.md` §4 makes mandatory:
/// a list-only screen does not count as complete for a module that also
/// supports create, edit and delete.
///
/// Write controls appear only for Admin/Super Admin. That is presentation,
/// not security — the API refuses the rest regardless, and a 403 is still
/// handled here.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canManage = app.currentRole?.canManageCatalog ?? false;

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('New Category'),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Budget Categories',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Allocation and remaining balance per category.',
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              Expanded(child: _Body(canManage: canManage)),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _openForm(BuildContext context, {Category? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryForm(existing: existing),
    );
  }
}

/// Loading, failed, empty and populated are four different states. Folding
/// them together is what made a dead backend look like an empty database.
class _Body extends StatelessWidget {
  const _Body({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.categoriesLoad;

    if (load.isLoading && app.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (load.hasFailed && app.categories.isEmpty) {
      return _Retry(
        message: load.error!,
        sessionExpired: load.sessionExpired,
        onRetry: () => app.loadCategories(),
      );
    }

    if (app.categories.isEmpty) {
      return _Empty(canManage: canManage);
    }

    return RefreshIndicator(
      onRefresh: () => app.loadCategories(),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: app.categories.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _CategoryCard(
          category: app.categories[i],
          canManage: canManage,
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.canManage});

  final Category category;
  final bool canManage;

  /// Spent is derived, not stored: allocation minus what the server says
  /// is left. Never computed from locally summed expenses.
  double get _spent => category.allocatedBudget - category.remainingBudget;

  double get _usedFraction => category.allocatedBudget <= 0
      ? 0
      : (_spent / category.allocatedBudget).clamp(0, 1).toDouble();

  bool get _isLow {
    final threshold = category.lowBalanceThreshold;
    return threshold != null && threshold > 0 && category.remainingBudget <= threshold;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(category.name, style: AppText.cardTitle),
              ),
              if (_isLow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.marigoldTint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Low balance',
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.marigoldText,
                    ),
                  ),
                ),
              if (canManage)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (value) {
                    if (value == 'edit') {
                      CategoriesScreen._openForm(context, existing: category);
                    } else {
                      _confirmDelete(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _usedFraction,
              minHeight: 6,
              backgroundColor: AppColors.trackBg,
              valueColor: AlwaysStoppedAnimation(
                _isLow ? AppColors.marigold : AppColors.indigo,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Figure(label: 'Allocated', value: category.allocatedBudget),
              const SizedBox(width: 18),
              _Figure(label: 'Spent', value: _spent),
              const SizedBox(width: 18),
              _Figure(label: 'Remaining', value: category.remainingBudget),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?', style: AppText.cardTitle),
        content: Text(
          '“${category.name}” will be removed. This cannot be undone, and '
          'the server will refuse if any event or expense still uses it.',
          style: AppText.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brick),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().deleteCategory(category);

    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Category deleted.'),
        duration: Duration(seconds: error == null ? 3 : 6),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption),
        const SizedBox(height: 2),
        Text('₱${value.toStringAsFixed(2)}', style: AppText.moneySmall),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open_outlined, size: 44, color: AppColors.inkFaint),
          const SizedBox(height: 14),
          const Text('No categories yet', style: AppText.cardTitle),
          const SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              canManage
                  ? 'Create one to start allocating budget. It will then be '
                      'selectable when recording events and expenses.'
                  : 'An administrator has not set up budget categories yet.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({
    required this.message,
    required this.sessionExpired,
    required this.onRetry,
  });

  final String message;
  final bool sessionExpired;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            const Text('Could not load categories', style: AppText.cardTitle),
            const SizedBox(height: 6),
            Text(message, style: AppText.caption, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            // Retrying an expired session just fails again — say so instead
            // of offering a button that cannot work.
            if (sessionExpired)
              const Text(
                'Sign out and sign in again to continue.',
                style: AppText.caption,
                textAlign: TextAlign.center,
              )
            else
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Create and edit share one form. `remaining_budget` is absent on purpose:
/// it is server-owned and there is no endpoint to set it.
class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.existing});

  final Category? existing;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _budgetController = TextEditingController(
    text: widget.existing?.allocatedBudget.toStringAsFixed(2) ?? '',
  );
  late final TextEditingController _thresholdController = TextEditingController(
    text: (widget.existing?.lowBalanceThreshold ?? 0).toStringAsFixed(2),
  );

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final budget = double.tryParse(_budgetController.text.trim());
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;

    if (name.isEmpty) {
      setState(() => _error = 'Give the category a name.');
      return;
    }
    // Budget fields allow zero but never a negative or unparseable amount.
    if (budget == null || budget < 0) {
      setState(() => _error = 'Enter an allocated budget of 0 or more.');
      return;
    }
    if (threshold < 0) {
      setState(() => _error = 'The low-balance threshold cannot be negative.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final app = context.read<AppState>();
    final error = _isEdit
        ? await app.updateCategory(
            widget.existing!,
            name: name == widget.existing!.name ? null : name,
            allocatedBudget:
                budget == widget.existing!.allocatedBudget ? null : budget,
            lowBalanceThreshold:
                threshold == (widget.existing!.lowBalanceThreshold ?? 0)
                    ? null
                    : threshold,
          )
        : await app.createCategory(
            name: name,
            allocatedBudget: budget,
            lowBalanceThreshold: threshold,
          );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Category updated.' : 'Category created.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Edit category' : 'New category',
                style: AppText.cardTitle),
            const SizedBox(height: 16),
            const Text('Name', style: AppText.caption),
            const SizedBox(height: 6),
            TextField(controller: _nameController),
            const SizedBox(height: 14),
            const Text('Allocated budget', style: AppText.caption),
            const SizedBox(height: 6),
            TextField(
              controller: _budgetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: '₱ '),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 4),
              const Text(
                'Changing this does not top up the remaining balance — that '
                'only moves when expenses are approved.',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text('Low-balance threshold', style: AppText.caption),
            const SizedBox(height: 6),
            TextField(
              controller: _thresholdController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: '₱ '),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brick.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _error!,
                  style: AppText.caption.copyWith(color: AppColors.brick),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Create category'),
            ),
          ],
        ),
      ),
    );
  }
}
