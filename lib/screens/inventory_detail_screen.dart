import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// One catalog item: its stock, its movement ledger, and the form for
/// recording a movement.
///
/// Quantity appears here only as a figure. There is no field to type it
/// into, because the only way it changes is a movement — which carries an
/// event, a reason and a direction.
class InventoryDetailScreen extends StatefulWidget {
  const InventoryDetailScreen({super.key, required this.item});

  final RemoteInventoryItem item;

  @override
  State<InventoryDetailScreen> createState() => _InventoryDetailScreenState();
}

class _InventoryDetailScreenState extends State<InventoryDetailScreen> {
  List<InventoryMovement>? _movements;
  String? _movementsError;
  bool _loading = false;

  late RemoteInventoryItem _item = widget.item;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMovements());
  }

  /// Keeps the header in step with the catalog after a movement changes it.
  RemoteInventoryItem get _current =>
      context
          .read<AppState>()
          .catalog
          .where((i) => i.id == _item.id)
          .firstOrNull ??
      _item;

  Future<void> _loadMovements() async {
    setState(() {
      _loading = true;
      _movementsError = null;
    });

    final outcome = await context.read<AppState>().loadMovements(_item);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _movements = outcome.movements;
      _movementsError = outcome.error;
      _item = _current;
    });
  }

  Future<void> _openMovementForm() async {
    final recorded = await BrutSheet.show<bool>(
      context,
      builder: (_) => _MovementSheet(item: _current),
    );
    if (recorded == true && mounted) await _loadMovements();
  }

  Future<void> _confirmDraft() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().confirmInventoryDraft(_item);
    if (!mounted) return;

    setState(() => _item = _current);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'Draft confirmed. Stock is unchanged — it was added when the '
                  'purchase was completed.',
        ),
        duration: Duration(seconds: error == null ? 5 : 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final item =
        app.catalog.where((i) => i.id == _item.id).firstOrNull ?? _item;
    final role = app.currentRole;

    final canMove =
        (role?.canRecordInventoryMovements ?? false) && item.isUsable;
    final canManage = role?.canManageCatalog ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              eyebrow: 'Catalog item',
              title: item.itemName,
              tone: item.isLowStock ? BrutTone.sun : BrutTone.brand,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (item.description?.isNotEmpty == true) ...[
                      Text(item.description!, style: AppText.caption),
                      const SizedBox(height: 14),
                    ],
                    _StockCard(item: item),

                    if (item.isDraft) ...[
                      const SizedBox(height: 14),
                      _DraftNotice(onConfirm: canManage ? _confirmDraft : null),
                    ],

                    if (canMove) ...[
                      const SizedBox(height: 14),
                      BrutButton(
                        label: 'Record movement',
                        icon: Icons.swap_vert,
                        onPressed: _openMovementForm,
                      ),
                    ] else if (!item.isUsable &&
                        (role?.canRecordInventoryMovements ?? false)) ...[
                      const SizedBox(height: 14),
                      BrutInlineMessage(
                        tone: BrutTone.sun,
                        icon: Icons.lock_outline,
                        text: item.isDraft
                            ? 'Movements are unavailable until this draft is '
                                  'confirmed by an administrator.'
                            : 'Movements need an event link. An administrator can '
                                  'repair this record.',
                      ),
                    ],

                    const SizedBox(height: 22),
                    BrutSectionTitle(
                      'Movement ledger',
                      aside: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : BrutIconButton(
                              icon: Icons.refresh,
                              label: 'Reload the ledger',
                              size: 30,
                              onPressed: _loadMovements,
                            ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Every change to stock, and why.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 12),
                    _Ledger(movements: _movements, error: _movementsError),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.item});

  final RemoteInventoryItem item;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: item.isLowStock ? BrutTone.sun : BrutTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('In stock'),
          const SizedBox(height: 4),
          Text('${item.quantity} ${item.unit}', style: AppText.moneyLarge),
          const SizedBox(height: 4),
          Text(
            item.isLowStock
                ? 'At or below the threshold of ${item.lowStockThreshold}.'
                : 'Threshold ${item.lowStockThreshold} ${item.unit}.',
            style: AppText.body.copyWith(fontSize: 12.5),
          ),
          if (item.location?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            BrutBadge(label: 'Kept at ${item.location}', mono: true),
          ],
        ],
      ),
    );
  }
}

class _DraftNotice extends StatelessWidget {
  const _DraftNotice({this.onConfirm});

  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: BrutTone.sun,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Unconfirmed draft'),
          const SizedBox(height: 6),
          Text(
            'This record was created by completing a purchase. Confirming it '
            'makes it usable for movements — it does not add stock again.',
            style: AppText.body.copyWith(fontSize: 12.5),
          ),
          if (onConfirm != null) ...[
            const SizedBox(height: 12),
            BrutButton(
              label: 'Confirm this item',
              tone: BrutTone.neutral,
              size: BrutSize.small,
              onPressed: onConfirm,
            ),
          ],
        ],
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.movements, required this.error});

  final List<InventoryMovement>? movements;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return BrutInlineMessage(text: error!, tone: BrutTone.coral);
    }
    if (movements == null) {
      return const Text('Loading…', style: AppText.caption);
    }
    if (movements!.isEmpty) {
      return const BrutEmptyState(
        title: 'No movements recorded yet',
        hint: 'Stock has not changed since this item was created.',
      );
    }

    final ordered = [...movements!]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return BrutCard(
      child: Column(
        children: [
          for (final movement in ordered) ...[
            _MovementRow(movement: movement),
            if (movement != ordered.last) const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final incoming = movement.isIncoming;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movement.type.label,
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
              if (movement.isFromPurchase) ...[
                const SizedBox(height: 4),
                const BrutBadge(label: 'From a purchase', mono: true),
              ],
              if (movement.reason?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(movement.reason!, style: AppText.caption),
              ],
              const SizedBox(height: 4),
              MonoLabel(BrutDateField.format(movement.createdAt.toLocal())),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // The sign is the point of a ledger row, so it is never dropped.
        BrutBadge(
          label: '${incoming ? '+' : ''}${movement.changeQty}',
          tone: incoming ? BrutTone.mint : BrutTone.coral,
          mono: true,
        ),
      ],
    );
  }
}

/// Recording a movement.
///
/// The form asks for a positive count even for Issue and Disposal, and the
/// sign is applied from the type. Asking anyone to type a minus is how you
/// get stock going the wrong way.
class _MovementSheet extends StatefulWidget {
  const _MovementSheet({required this.item});

  final RemoteInventoryItem item;

  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _countController = TextEditingController(text: '1');
  final _reasonController = TextEditingController();

  InventoryMovementType _type = InventoryMovementType.issue;
  String? _eventId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to the item's own event; a movement still needs one chosen.
    _eventId = widget.item.eventId;
  }

  @override
  void dispose() {
    _countController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// What this movement would leave in stock, so the effect is visible
  /// before it is committed.
  int? get _projected {
    final change = signedChangeFor(_type, _countController.text);
    return change == null ? null : widget.item.quantity + change;
  }

  Future<void> _submit() async {
    if (_eventId == null) {
      setState(() => _error = 'Choose the event this movement is for.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await context.read<AppState>().recordInventoryMovement(
      widget.item,
      type: _type,
      eventId: _eventId!,
      count: _countController.text,
      reason: _reasonController.text,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final events = context
        .watch<AppState>()
        .events
        .where((e) => e.remoteId != null)
        .toList();
    final projected = _projected;

    return BrutSheet(
      title: 'Move ${widget.item.itemName}',
      footer: BrutButton(
        label: 'Record movement',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Recording…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.item.quantity} ${widget.item.unit} in stock now.',
            style: AppText.caption,
          ),
          const SizedBox(height: 18),
          BrutDropdown<InventoryMovementType>(
            label: 'What happened',
            value: _type,
            hint: 'Select',
            items: [
              for (final t in selectableMovementTypes)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 6),
          Text(_type.hint, style: AppText.caption),
          const SizedBox(height: 14),
          BrutDropdown<String>(
            label: 'Event',
            value: _eventId,
            hint: 'Select an event',
            items: [
              for (final e in events)
                DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
            ],
            onChanged: (v) => setState(() => _eventId = v),
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'How many ${widget.item.unit}',
            controller: _countController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            _type == InventoryMovementType.adjustment
                // The one case where the user genuinely picks the
                // direction, so a minus is meaningful here.
                ? 'Use a minus for a downward correction.'
                : 'A positive count — the direction follows from what '
                      'happened.',
            style: AppText.caption,
          ),
          if (projected != null) ...[
            const SizedBox(height: 10),
            BrutInlineMessage(
              tone: projected < 0 ? BrutTone.coral : BrutTone.neutral,
              icon: projected < 0 ? Icons.block : Icons.arrow_forward,
              text: projected < 0
                  ? 'That would leave $projected — stock cannot go below '
                        'zero.'
                  : 'Stock would become $projected ${widget.item.unit}.',
            ),
          ],
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Reason',
            controller: _reasonController,
            hint: 'Why this is being moved',
            maxLength: InventoryService.maxReasonLength,
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
