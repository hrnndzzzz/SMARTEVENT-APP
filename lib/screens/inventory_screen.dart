import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'inventory_detail_screen.dart';
import 'notifications_screen.dart';

/// The equipment catalog and its stock.
///
/// Quantity is never editable here. Stock moves only by recording a
/// movement, so every change carries a reason and shows up in the ledger.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadCatalog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.catalogLoad;
    final canManage = app.currentRole?.canManageCatalog ?? false;

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _NewItemSheet(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New Item'),
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
                'Inventory & Equipment',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Stock changes only through recorded movements.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              const _FilterBar(),
              const SizedBox(height: 12),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.catalog.isEmpty =>
                    const Center(child: CircularProgressIndicator()),
                  _ when load.hasFailed && app.catalog.isEmpty => Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(load.error!,
                                style: AppText.caption,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: app.loadCatalog,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ when app.catalog.isEmpty => _Empty(canManage: canManage),
                  _ => RefreshIndicator(
                      onRefresh: app.loadCatalog,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: app.catalog.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _ItemCard(item: app.catalog[i]),
                      ),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final drafts = app.catalogDraftFilter == true;
    final missing = app.catalogMissingEventOnly;
    final all = !drafts && !missing;
    // Both of these are administrator work queues, not general filters.
    final isAdmin = app.currentRole?.isAdministrator ?? false;

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All',
            selected: all,
            onTap: () => app.applyCatalogFilter(),
          ),
          if (isAdmin)
            _Chip(
              label: 'Unconfirmed drafts',
              selected: drafts,
              onTap: () => app.applyCatalogFilter(isDraft: true),
            ),
          if (isAdmin)
            _Chip(
              label: 'Needs event link',
              selected: missing,
              onTap: () => app.applyCatalogFilter(missingEventOnly: true),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.indigo : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.indigo : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final RemoteInventoryItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => InventoryDetailScreen(item: item)),
      ),
      child: Container(
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
                Expanded(child: Text(item.itemName, style: AppText.cardTitle)),
                Text(
                  '${item.quantity} ${item.unit}',
                  style: AppText.moneySmall.copyWith(
                    color: item.isLowStock
                        ? AppColors.marigoldText
                        : AppColors.ink,
                  ),
                ),
              ],
            ),
            if (item.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(item.description!, style: AppText.caption),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (item.isDraft)
                  const _Tag(
                    label: 'Unconfirmed draft',
                    fg: AppColors.marigoldText,
                    bg: AppColors.marigoldTint,
                  ),
                if (item.isLowStock)
                  _Tag(
                    label: 'Low stock (≤ ${item.lowStockThreshold})',
                    fg: AppColors.marigoldText,
                    bg: AppColors.marigoldTint,
                  ),
                if (item.needsEventLink)
                  const _Tag(
                    label: 'No event link',
                    fg: AppColors.brick,
                    bg: Color(0xFFFBEAE7),
                  ),
                if (item.location?.isNotEmpty == true)
                  _Tag(
                    label: item.location!,
                    fg: AppColors.inkMuted,
                    bg: AppColors.trackBg,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final filtered = context.watch<AppState>().catalogDraftFilter != null ||
        context.watch<AppState>().catalogMissingEventOnly;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 44, color: AppColors.inkFaint),
          const SizedBox(height: 14),
          Text(
            filtered ? 'Nothing matches this filter' : 'No items yet',
            style: AppText.cardTitle,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              filtered
                  ? 'Nothing needs attention here.'
                  : canManage
                      ? 'Add equipment to track, or complete a purchase to '
                          'have items created for you.'
                      : 'Equipment appears here once an administrator adds it.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Creating a catalog item, with optional documented opening stock.
class _NewItemSheet extends StatefulWidget {
  const _NewItemSheet();

  @override
  State<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends State<_NewItemSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '0');
  final _unitController = TextEditingController(text: 'pcs');
  final _thresholdController = TextEditingController(text: '5');
  final _locationController = TextEditingController();
  final _reasonController = TextEditingController(text: 'Opening stock');

  String? _eventId;
  InitialStockType _initialType = InitialStockType.openingBalance;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _thresholdController.dispose();
    _locationController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_eventId == null) return 'Choose the event this belongs to.';
    if (_nameController.text.trim().isEmpty) return 'Give the item a name.';

    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity < 0) {
      return 'Starting stock must be a whole number, zero or more.';
    }
    final threshold = int.tryParse(_thresholdController.text.trim());
    if (threshold == null || threshold < 0) {
      return 'The low-stock threshold must be zero or more.';
    }
    if (_unitController.text.trim().isEmpty) return 'Enter a unit.';
    if (_reasonController.text.trim().isEmpty) {
      return 'Give a reason for the starting stock.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final app = context.read<AppState>();
    final error = await app.createInventoryItem(
      eventId: _eventId!,
      itemName: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      quantity: int.parse(_quantityController.text.trim()),
      unit: _unitController.text.trim(),
      lowStockThreshold: int.parse(_thresholdController.text.trim()),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      initialTransactionType: _initialType,
      reason: _reasonController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item added.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final events =
        context.watch<AppState>().events.where((e) => e.remoteId != null).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New inventory item', style: AppText.cardTitle),
              const SizedBox(height: 16),

              const Text('Event', style: AppText.caption),
              const SizedBox(height: 6),
              _Picker<String>(
                value: _eventId,
                hint: events.isEmpty ? 'No events available' : 'Select an event',
                items: [
                  for (final e in events)
                    DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              const SizedBox(height: 14),

              _field('Item name', _nameController),
              _field('Description', _descriptionController),
              Row(
                children: [
                  Expanded(
                    child: _field('Starting stock', _quantityController,
                        number: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _field('Unit', _unitController)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _field('Low-stock threshold', _thresholdController,
                        number: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _field('Location', _locationController)),
                ],
              ),

              const Text('How this stock was obtained', style: AppText.caption),
              const SizedBox(height: 2),
              const Text(
                'Newly bought goods are not opening stock — complete the '
                'purchase on the expense instead, so the payment is recorded.',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              _Picker<InitialStockType>(
                value: _initialType,
                hint: 'Select',
                items: [
                  for (final t in InitialStockType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _initialType = v ?? _initialType),
              ),
              const SizedBox(height: 14),
              _field('Reason', _reasonController),

              if (_error != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brick.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: AppText.caption.copyWith(color: AppColors.brick)),
                ),
              ],

              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add item'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: number ? TextInputType.number : TextInputType.text,
          ),
        ],
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(hint,
              style: const TextStyle(
                fontFamily: AppText.bodyFamily,
                fontSize: 13,
                color: AppColors.inkFaint,
              )),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
