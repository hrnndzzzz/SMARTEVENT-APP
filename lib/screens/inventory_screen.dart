import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
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
              label: Text('New item', style: AppText.buttonLabel),
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
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Inventory', style: AppText.screenTitle),
              const SizedBox(height: 4),
              const Text(
                'Stock changes only through recorded movements.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              const _FilterBar(),
              const SizedBox(height: 12),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.catalog.isEmpty => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  _ when load.hasFailed && app.catalog.isEmpty => BrutRetry(
                    title: 'Could not load inventory',
                    message: load.error,
                    sessionExpired: load.sessionExpired,
                    onRetry: app.loadCatalog,
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

    return BrutChipBar(
      children: [
        BrutChip(
          label: 'All',
          selected: all,
          onTap: () => app.applyCatalogFilter(),
        ),
        if (isAdmin)
          BrutChip(
            label: 'Unconfirmed drafts',
            selected: drafts,
            onTap: () => app.applyCatalogFilter(isDraft: true),
          ),
        if (isAdmin)
          BrutChip(
            label: 'Needs event link',
            selected: missing,
            onTap: () => app.applyCatalogFilter(missingEventOnly: true),
          ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final RemoteInventoryItem item;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => InventoryDetailScreen(item: item)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(item.itemName, style: AppText.cardTitle)),
              const SizedBox(width: 10),
              Text(
                '${item.quantity} ${item.unit}',
                style: AppText.moneyLarge.copyWith(fontSize: 16),
              ),
            ],
          ),
          if (item.description?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(item.description!, style: AppText.caption),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.isDraft)
                const BrutBadge(label: 'Unconfirmed draft', tone: BrutTone.sun),
              if (item.isLowStock)
                BrutBadge(
                  label: 'Low stock (≤ ${item.lowStockThreshold})',
                  tone: BrutTone.sun,
                ),
              if (item.needsEventLink)
                const BrutBadge(label: 'No event link', tone: BrutTone.coral),
              if (item.location?.isNotEmpty == true)
                BrutBadge(label: item.location!, mono: true),
            ],
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
    final app = context.watch<AppState>();
    final filtered =
        app.catalogDraftFilter != null || app.catalogMissingEventOnly;

    return Center(
      child: BrutEmptyState(
        icon: Icons.inventory_2_outlined,
        title: filtered ? 'Nothing matches this filter' : 'No items yet',
        hint: filtered
            ? 'Nothing needs attention here.'
            : canManage
            ? 'Add equipment to track, or complete a purchase to have '
                  'items created for you.'
            : 'Equipment appears here once an administrator adds it.',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item added.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = context
        .watch<AppState>()
        .events
        .where((e) => e.remoteId != null)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          border: AppBorders.all,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrutSectionTitle('New inventory item'),
              const SizedBox(height: 18),
              BrutDropdown<String>(
                label: 'Event',
                value: _eventId,
                hint: events.isEmpty
                    ? 'No events available'
                    : 'Select an event',
                items: [
                  for (final e in events)
                    DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              const SizedBox(height: 14),
              BrutTextField(
                label: 'Item name',
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                label: 'Description',
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BrutTextField(
                      label: 'Starting stock',
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BrutTextField(
                      label: 'Unit',
                      controller: _unitController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BrutTextField(
                      label: 'Low-stock threshold',
                      controller: _thresholdController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BrutTextField(
                      label: 'Location',
                      controller: _locationController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              BrutDropdown<InitialStockType>(
                label: 'How this stock was obtained',
                value: _initialType,
                hint: 'Select',
                items: [
                  for (final t in InitialStockType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) =>
                    setState(() => _initialType = v ?? _initialType),
              ),
              const SizedBox(height: 6),
              const Text(
                'Newly bought goods are not opening stock — complete the '
                'purchase on the expense instead, so the payment is '
                'recorded.',
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                label: 'Reason',
                controller: _reasonController,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                BrutInlineMessage(text: _error!, tone: BrutTone.coral),
              ],
              const SizedBox(height: 20),
              BrutButton(
                label: 'Add item',
                size: BrutSize.large,
                busy: _submitting,
                busyLabel: 'Adding…',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
