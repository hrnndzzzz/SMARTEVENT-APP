import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/event_picker_items.dart';
import '../widgets/floating_peek.dart';
import '../widgets/last_change_note.dart';
import '../widgets/module_band.dart';
import '../widgets/stat_grid.dart';
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
  _ItemSort _sort = _ItemSort.place;

  /// What was typed into the search box, already trimmed and lowered.
  String _query = '';
  final _search = TextEditingController();

  /// One storage place, or null for all of them. Set from the places
  /// sheet, which is the only screen that lists them.
  String? _place;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Name, description and location, so "cabinet" finds both an item
  /// called one and everything kept in one.
  bool _matchesQuery(RemoteInventoryItem item) {
    if (_query.isEmpty) return true;
    return [
      item.itemName,
      item.description ?? '',
      item.location ?? '',
    ].any((field) => field.toLowerCase().contains(_query));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadCatalog();
    });
  }

  /// The heading an item files under. One definition, used by the
  /// filter, the places sheet and the grouping, so they cannot drift
  /// apart and show three different counts for the same shelf.
  static String _placeOf(RemoteInventoryItem item) =>
      (item.location?.trim().isNotEmpty ?? false)
      ? item.location!.trim()
      : _unplaced;

  static const _unplaced = 'No location recorded';

  /// What the empty state should say was not found. Naming the search
  /// first matters: "nothing low stock" is confusing when the real
  /// reason nothing showed up is a typo in the search box.
  String get _emptyLabel {
    if (_query.isNotEmpty) return 'matching "$_query"';
    if (_place != null) return 'in $_place';
    return _stock.label.toLowerCase();
  }

  Future<void> _choosePlace(BuildContext context) async {
    final catalog = context.read<AppState>().catalog;
    final counts = <String, int>{};
    for (final item in catalog) {
      counts.update(_placeOf(item), (n) => n + 1, ifAbsent: () => 1);
    }
    final places = counts.keys.toList()
      ..sort((a, b) {
        if (a == _unplaced) return 1;
        if (b == _unplaced) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    if (!context.mounted) return;
    await BrutSheet.show<void>(
      context,
      builder: (sheetContext) => BrutSheet(
        title: 'Storage places',
        subtitle: places.isEmpty
            ? 'Nothing has a location yet.'
            : '${places.length} in the catalogue',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrutListRow(
              title: 'Everywhere',
              meta: '${catalog.length} items',
              marker: const BrutIconTile(
                size: 32,
                icon: Icons.all_inbox_outlined,
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _place = null);
              },
            ),
            const SizedBox(height: 8),
            for (final place in places) ...[
              BrutListRow(
                title: place,
                meta:
                    '${counts[place]} '
                    '${counts[place] == 1 ? 'item' : 'items'}',
                marker: BrutIconTile(
                  size: 32,
                  icon: place == _unplaced
                      ? Icons.help_outline
                      : Icons.warehouse_outlined,
                  tone: place == _unplaced ? BrutTone.sun : BrutTone.neutral,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _place = place);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
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
      // One scroll for the whole page, rather than a fixed top half and
      // a list scrolling inside the bottom one.
      //
      // The band, the last-change note, four figures, a line of prose
      // and two rows of filters came to about half the screen and none
      // of it moved, so the catalogue was read through a letterbox.
      // Reported as: "pwede ba kapag nag scroll up, nag-scroll up din
      // lahat — para hindi yung half lang yung nakikita?"
      //
      // Pull-to-refresh moves up here with it; the list had its own.
      onRefresh: app.loadCatalog,
      // Clear of the New item button.
      bottomPadding: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModuleBand(
            module: Module.inventory,
            subtitle: 'Stock changes only through recorded movements.',
          ),
          const SizedBox(height: AppLayout.tight),
          const LastChangeNote(area: 'inventory'),
          const SizedBox(height: AppLayout.between),

          // Where the module stands, before the list of what is in it.
          //
          // This page used to go from its coloured band straight into
          // two paragraphs of explanation and a row of filters, so the
          // top third of the screen was prose and the first thing you
          // could actually use was below it. The same four figures are
          // in the list — but only if you read every row and count.
          _Figures(items: app.catalog),
          const SizedBox(height: AppLayout.between),

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
          // Find a thing by name before narrowing by anything else.
          // A catalogue you can only browse is a catalogue you have to
          // already know your way around.
          BrutTextField(
            controller: _search,
            label: 'Search',
            hint: 'Name, description or where it is kept',
            prefixIcon: Icons.search,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _InventorySortButton(
                    sort: _sort,
                    onChanged: (value) => setState(() => _sort = value),
                  ),
                ),
              ),
              const SizedBox(width: AppLayout.tight),
              // Where everything is kept, which until now could only be
              // learned by scrolling the whole list and reading the
              // headings.
              BrutButton(
                label: _place ?? 'Places',
                icon: Icons.warehouse_outlined,
                tone: _place == null ? BrutTone.neutral : BrutTone.dark,
                size: BrutSize.small,
                expand: false,
                onPressed: () => _choosePlace(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
          // No longer Expanded: there is one scroll now and this is the
          // bottom of it. The three states that used to fill the
          // remaining height are given a height of their own instead,
          // since a Center with nothing to centre inside collapses.
          switch (load) {
            _ when load.isLoading && app.catalog.isEmpty => const SizedBox(
              height: 240,
              child: Center(child: BrutSpinner()),
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
                  if (_stock.matches(item) &&
                      _matchesQuery(item) &&
                      (_place == null || _placeOf(item) == _place))
                    item,
              ],
              sort: _sort,
              onRefresh: () => app.refreshList(app.loadCatalog),
              emptyLabel: _emptyLabel,
              canMove: canMove,
            ),
          },
        ],
      ),
    );
  }
}

/// Items, low stock, none left, and where they live.
///
/// Counted off the loaded catalogue rather than asked for separately:
/// a second source for the same four numbers is a second thing that
/// can disagree with the list underneath it.
class _Figures extends StatelessWidget {
  const _Figures({required this.items});

  final List<RemoteInventoryItem> items;

  @override
  Widget build(BuildContext context) {
    // None left is its own state, not a low one — isLowStock is true at
    // zero — so an empty shelf is counted once, under "None left", and
    // "Low stock" means low rather than gone. The badges on the rows
    // below already make exactly this distinction.
    final empty = items.where((i) => i.quantity <= 0).length;
    final low = items.where((i) => i.quantity > 0 && i.isLowStock).length;
    final locations = items
        .map((i) => i.location)
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toSet()
        .length;

    return StatGrid(
      cells: [
        StatCell(
          label: 'Items',
          value: '${items.length}',
          // A count of what exists is context, not a verdict.
          tone: BrutTone.neutral,
        ),
        StatCell(
          label: 'Locations',
          value: '$locations',
          tone: BrutTone.neutral,
        ),
        StatCell(
          label: 'Low stock',
          value: '$low',
          tone: low == 0 ? BrutTone.neutral : BrutTone.sun,
          hint: low == 0 ? null : 'At or below the threshold',
        ),
        StatCell(
          label: 'None left',
          value: '$empty',
          tone: empty == 0 ? BrutTone.neutral : BrutTone.coral,
          hint: empty == 0 ? null : 'Nothing on the shelf',
        ),
      ],
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
                  // Amber, not the coral "None left" wears. Low and
                  // gone were the same red, so the row said they were
                  // the same thing while the comment above and the
                  // figures at the top of the screen both say they are
                  // not.
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
    required this.sort,
    required this.onRefresh,
    required this.emptyLabel,
    required this.canMove,
  });

  final List<RemoteInventoryItem> items;

  /// Whether to keep the location headings, and the order within
  /// whatever is drawn.
  final _ItemSort sort;
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
          hint: 'Clear the search, or tap All to see the whole catalogue.',
        ),
      );
    }

    // Sorted by something other than place, the headings would be a
    // lie: an A–Z list printed under five shelf names is five A–Z
    // lists. So the groups go and one flat ordered list takes over.
    if (!sort.groups) {
      final ordered = [...items]..sort(sort.compare);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in ordered) ...[
            _ItemCard(
              item: item,
              onMove: (canMove && item.isUsable)
                  ? () async {
                      final moved = await showMovementSheet(context, item);
                      if (moved) await onRefresh();
                    }
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
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

    // A Column, not a ListView. The page scrolls as one now, so a
    // second scrollable inside it would be the letterbox again — and
    // pull-to-refresh lives on the page, where the gesture works
    // whether or not there is a list under your thumb.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final place in places) ...[
          BrutSectionTitle(
            place,
            aside: MonoLabel('${byPlace[place]!.length}'),
          ),
          const SizedBox(height: AppLayout.between),
          for (final item in byPlace[place]!..sort(sort.compare)) ...[
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
    );
  }
}

/// How the catalogue is ordered.
///
/// [place] is the order this screen has always drawn — grouped by where
/// a thing is kept — and it stays the default, because "which shelf" is
/// how people look for equipment. The other three answer different
/// questions and flatten the groups to do it.
enum _ItemSort {
  place('By place', Icons.warehouse_outlined),
  nameAsc('Name A–Z', Icons.sort_by_alpha),
  nameDesc('Name Z–A', Icons.sort_by_alpha),
  mostStock('Most stock', Icons.arrow_downward),
  leastStock('Least stock', Icons.arrow_upward);

  const _ItemSort(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Whether the list keeps its location headings. Only [place] does:
  /// sorting by name and then printing the names under five headings
  /// is not a sorted list.
  bool get groups => this == _ItemSort.place;

  int compare(RemoteInventoryItem a, RemoteInventoryItem b) => switch (this) {
    _ItemSort.place || _ItemSort.nameAsc => a.itemName.toLowerCase().compareTo(
      b.itemName.toLowerCase(),
    ),
    _ItemSort.nameDesc => b.itemName.toLowerCase().compareTo(
      a.itemName.toLowerCase(),
    ),
    _ItemSort.mostStock => b.quantity.compareTo(a.quantity),
    _ItemSort.leastStock => a.quantity.compareTo(b.quantity),
  };
}

class _InventorySortButton extends StatelessWidget {
  const _InventorySortButton({required this.sort, required this.onChanged});

  final _ItemSort sort;
  final ValueChanged<_ItemSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return BrutButton(
      icon: sort.icon,
      label: sort.label,
      trailingIcon: Icons.expand_more,
      tone: sort == _ItemSort.place ? BrutTone.neutral : BrutTone.dark,
      size: BrutSize.small,
      expand: false,
      onPressed: () async {
        final picked = await showFloatingPeek<_ItemSort>(
          context,
          title: 'Sort inventory',
          subtitle: sort.label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in _ItemSort.values) ...[
                BrutListRow(
                  title: option.label,
                  marker: BrutIconTile(
                    size: 32,
                    icon: option.icon,
                    tone: option == sort ? BrutTone.dark : BrutTone.neutral,
                  ),
                  trailing: option == sort
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.of(context).pop(option),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
