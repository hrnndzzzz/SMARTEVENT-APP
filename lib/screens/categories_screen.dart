import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/models/category.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../theme/peso.dart';

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
    final canManage =
        !context.watch<AppState>().isOfflineViewing &&
        (app.currentRole?.canManageCatalog ?? false);

    return BrutScreen(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => openForm(context),
              icon: const Icon(Icons.add),
              label: Text('New category', style: AppText.buttonLabel),
            )
          : null,
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Budget categories', style: AppText.display),
          const SizedBox(height: 4),
          const Text(
            'Allocation and remaining balance per category.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          Expanded(child: _Body(canManage: canManage)),
        ],
      ),
    );
  }

  /// Opens the create-or-edit form.
  ///
  /// Public because a category is picked in places other than this
  /// screen — recording an expense, above all — and sending someone off
  /// to make one meant losing the form they were part-way through.
  static Future<void> openForm(BuildContext context, {Category? existing}) {
    return BrutSheet.show<void>(
      context,
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
      return Center(child: BrutSpinner());
    }

    if (load.hasFailed && app.categories.isEmpty) {
      return BrutRetry(
        title: 'Could not load categories',
        message: load.error,
        sessionExpired: load.sessionExpired,
        onRetry: () => app.loadCategories(),
      );
    }

    if (app.categories.isEmpty) {
      return _Empty(canManage: canManage);
    }

    return RefreshIndicator(
      onRefresh: () => app.refreshList(app.loadCategories),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: app.categories.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _CategoryCard(category: app.categories[i], canManage: canManage),
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
    return threshold != null &&
        threshold > 0 &&
        category.remainingBudget <= threshold;
  }

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(category.name, style: AppText.cardTitle)),
              if (_isLow) ...[
                const BrutBadge(label: 'Low balance', tone: BrutTone.coral),
                const SizedBox(width: 4),
              ],
              if (canManage)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (value) {
                    if (value == 'edit') {
                      CategoriesScreen.openForm(context, existing: category);
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
          const SizedBox(height: 12),
          BrutProgressBar(
            value: _usedFraction,
            tone: _isLow ? BrutTone.coral : BrutTone.brand,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Figure(label: 'Allocated', value: category.allocatedBudget),
              const SizedBox(width: 16),
              _Figure(label: 'Spent', value: _spent),
              const SizedBox(width: 16),
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
          BrutButton(
            label: 'Delete',
            tone: BrutTone.coral,
            size: BrutSize.small,
            expand: false,
            onPressed: () => Navigator.pop(dialogContext, true),
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MonoLabel(label),
          const SizedBox(height: 4),
          Text(
            '${peso(value)}',
            style: AppText.number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BrutEmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No categories yet',
        hint: canManage
            ? 'Create one to start allocating budget. It will then be '
                  'selectable when recording events and expenses.'
            : 'An administrator has not set up budget categories yet.',
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
  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
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
            allocatedBudget: budget == widget.existing!.allocatedBudget
                ? null
                : budget,
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
        SnackBar(
          content: Text(_isEdit ? 'Category updated.' : 'Category created.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrutSheet(
      title: _isEdit ? 'Edit category' : 'New category',
      footer: BrutButton(
        label: _isEdit ? 'Save changes' : 'Create category',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Saving…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutTextField(
            label: 'Name',
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Allocated budget',
            controller: _budgetController,
            prefixIcon: Icons.payments_outlined,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 6),
            const Text(
              'Changing this does not top up the remaining balance — that '
              'only moves when expenses are approved.',
              style: AppText.caption,
            ),
          ],
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Low-balance threshold',
            controller: _thresholdController,
            prefixIcon: Icons.payments_outlined,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          ],
        ],
      ),
    );
  }
}
