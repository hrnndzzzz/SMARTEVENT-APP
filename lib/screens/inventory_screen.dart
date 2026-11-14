import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/event_picker_items.dart';
import '../widgets/last_change_note.dart';
import '../widgets/module_band.dart';
import 'inventory_detail_screen.dart';
import '../theme/module_identity.dart';

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
  _StockFilter _stock = _StockFilter.all;

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
    final offline = context.watch<AppState>().isOfflineViewing;
    final canManage =
        !offline && (app.currentRole?.canAddRemoveInventoryItems ?? false);
    // Adding an item and moving stock are different permissions: a
    // treasurer moves stock but does not shape the catalogue. The screen
    // offered neither, so a treasurer saw a list and no way to act on it.
    final canMove =
        !offline && (app.currentRole?.canRecordInventoryMovements ?? false);

    return BrutScreen(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => BrutSheet.show<void>(
                context,
                builder: (_) => const _NewItemSheet(),
              ),
              icon: const Icon(Icons.add),
              label: Text('New item', style: AppText.buttonLabel),
            )
          : null,
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModuleBand(
            module: Module.inventory,
            subtitle: 'Stock changes only through recorded movements.',
          ),
          const SizedBox(height: AppLayout.tight),
          const LastChangeNote(area: 'inventory'),
          const SizedBox(height: 2),

          // Where items come from was explained only on the empty
          // screen, so anyone with a list in front of them could not
          // tell whether an item was theirs to make or something the
          // system had produced. Kept to one line: this sits above the
          // list, and the keyboard has to fit under it.
          //
          // Which of those two is available depends on the role, and an
          // absent button looks the same as a missing feature. Saying
          // whose job it is beats leaving a treasurer wondering whether
          // the screen is broken.
          Text(
            canManage
                ? 'They come from completing a purchase, or you add one '
                      'by hand.'
                : 'They come from completing a purchase. Adding and '
                      'removing items is an officer, adviser or '
                      'administrator job.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          const _FilterBar(),
          const SizedBox(height: 8),
          BrutChipBar(
            children: [
              for (final option in _StockFilter.values)
                BrutChip(
                  label: option.label,
                  selected: option == _stock,
                  tone: option.tone,
                  onTap: () => setState(() => _stock = option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (load) {
              _ when load.isLoading && app.catalog.isEmpty => const Center(
                child: BrutSpinner(),
              ),
              _ when load.hasFailed && app.catalog.isEmpty => BrutRetry(
                title: 'Could not load inventory',
                message: load.error,
                sessionExpired: load.sessionExpired,
                onRetry: app.loadCatalog,
              ),
              _ when app.catalog.isEmpty => _Empty(canManage: canManage),
              _ => _Grouped(
                items: [
                  for (final item in app.catalog)
                    if (_stock.matches(item)) item,
                ],
                onRefresh: () => app.refreshList(app.loadCatalog),
                emptyLabel: _stock.label.toLowerCase(),
                canMove: canMove,
              ),
            },
          ),
        ],
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

    // Without them there is one chip, already selected, filtering
    // nothing — a control that cannot be used or unused. The status bar
    // below is the only filter anyone else has.
    if (!isAdmin) return const SizedBox.shrink();

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
  const _ItemCard({required this.item, required this.onMove});

  final RemoteInventoryItem item;

  /// Null when this account may not move stock, or the item cannot take
  /// a movement yet — a draft has no event to move against.
  final VoidCallback? onMove;

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
              // Issuing stock is the common errand on this screen and it
              // was only reachable by opening the item first, which is a
              // tap nobody standing at a cupboard wants to spend.
              if (onMove != null) ...[
                const SizedBox(width: 6),
                BrutIconButton(
                  icon: Icons.swap_vert,
                  label: 'Record a movement for ${item.itemName}',
                  onPressed: onMove,
                  size: 34,
                ),
              ],
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
                // Says where it came from, not only what state it is in:
                // "draft" alone does not tell you a purchase made it.
                const BrutBadge(label: 'From a purchase', tone: BrutTone.sun),
              // None left is its own state, not a low one. isLowStock is
              // true at zero, so the badge used to call an empty shelf
              // low stock while the filter above counted it as none
              // left — the badge and the filter disagreeing about the
              // same row.
              if (item.quantity <= 0)
                const BrutBadge(label: 'None left', tone: BrutTone.coral)
              else if (item.isLowStock)
                BrutBadge(
                  label: 'Low stock (≤ ${item.lowStockThreshold})',
                  tone: BrutTone.coral,
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
    final events = eventPickerItems(
      context.watch<AppState>().events,
      keep: _eventId,
    );

    return BrutSheet(
      title: 'New inventory item',
      footer: BrutButton(
        label: 'Add item',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Adding…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutDropdown<String>(
            label: 'Event',
            value: _eventId,
            hint: events.isEmpty ? 'No events available' : 'Select an event',
            items: events,
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
            onChanged: (v) => setState(() => _initialType = v ?? _initialType),
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
        ],
      ),
    );
  }
}

/// What state the stock is in, as something you can ask for.
enum _StockFilter {
  all('All', null),
  available('Available', BrutTone.mint),
  low('Low stock', BrutTone.coral),
  none('None left', BrutTone.neutral);

  const _StockFilter(this.label, this.tone);

  final String label;
  final BrutTone? tone;

  bool matches(RemoteInventoryItem item) => switch (this) {
    _StockFilter.all => true,
    _StockFilter.none => item.quantity <= 0,
    _StockFilter.low => item.quantity > 0 && item.isLowStock,
    _StockFilter.available => item.quantity > 0 && !item.isLowStock,
  };
}

/// The catalogue, under the place each thing is kept.
///
/// A flat list of forty items is a list you read end to end to answer
/// "what is in the faculty office". Storage is the question people
/// actually arrive with, so it is the heading; anything with no location
/// recorded gathers at the bottom rather than being hidden.
class _Grouped extends StatelessWidget {
  const _Grouped({
    required this.items,
    required this.onRefresh,
    required this.emptyLabel,
    required this.canMove,
  });

  final List<RemoteInventoryItem> items;
  final Future<void> Function() onRefresh;
  final String emptyLabel;

  /// Whether this account may record stock movements at all.
  final bool canMove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: BrutEmptyState(
          icon: Icons.filter_alt_outlined,
          title: 'Nothing $emptyLabel',
          hint: 'Tap All to see the whole catalogue.',
        ),
      );
    }

    const unplaced = 'No location recorded';
    final byPlace = <String, List<RemoteInventoryItem>>{};
    for (final item in items) {
      final place = (item.location?.trim().isNotEmpty ?? false)
          ? item.location!.trim()
          : unplaced;
      byPlace.putIfAbsent(place, () => []).add(item);
    }
    final places = byPlace.keys.toList()
      ..sort((a, b) {
        if (a == unplaced) return 1;
        if (b == unplaced) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final place in places) ...[
            BrutSectionTitle(
              place,
              aside: MonoLabel('${byPlace[place]!.length}'),
            ),
            const SizedBox(height: AppLayout.between),
            for (final item in byPlace[place]!) ...[
              _ItemCard(
                item: item,
                // A draft has no event to move stock against, so it is
                // confirmed from its own page before anything moves.
                onMove: (canMove && item.isUsable)
                    ? () async {
                        final moved = await showMovementSheet(context, item);
                        if (moved) await onRefresh();
                      }
                    : null,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: AppLayout.tight),
          ],
        ],
      ),
    );
  }
}
