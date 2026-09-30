import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/scope_picker.dart';

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
      context.read<AppState>().catalog.where((i) => i.id == _item.id).firstOrNull ??
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
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
        content: Text(error ??
            'Draft confirmed. Stock is unchanged — it was added when the '
                'purchase was completed.'),
        duration: Duration(seconds: error == null ? 5 : 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final item = app.catalog.where((i) => i.id == _item.id).firstOrNull ?? _item;
    final role = app.currentRole;

    final canMove = (role?.canRecordInventoryMovements ?? false) && item.isUsable;
    final canManage = role?.canManageCatalog ?? false;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 10),
              Text(
                item.itemName,
                style: const TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              if (item.description?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(item.description!, style: AppText.caption),
              ],
              const SizedBox(height: 14),

              _StockCard(item: item),

              if (item.isDraft) ...[
                const SizedBox(height: 14),
                _DraftNotice(
                  onConfirm: canManage ? _confirmDraft : null,
                ),
              ],

              if (canMove) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _openMovementForm,
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: const Text('Record movement'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ] else if (!item.isUsable &&
                  (role?.canRecordInventoryMovements ?? false)) ...[
                const SizedBox(height: 14),
                Text(
                  item.isDraft
                      ? 'Movements are unavailable until this draft is '
                          'confirmed by an administrator.'
                      : 'Movements need an event link. An administrator can '
                          'repair this record.',
                  style: AppText.caption,
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text('Movement ledger', style: AppText.cardTitle),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      onPressed: _loadMovements,
                      icon: const Icon(Icons.refresh, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Every change to stock, and why.',
                style: AppText.caption,
              ),
              const SizedBox(height: 10),
              _Ledger(movements: _movements, error: _movementsError),
            ],
          ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.isLowStock ? AppColors.marigoldTint : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isLowStock ? AppColors.marigold : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${item.quantity} ${item.unit}', style: AppText.moneyLarge),
          const SizedBox(height: 2),
          Text(
            item.isLowStock
                ? 'At or below the threshold of ${item.lowStockThreshold}.'
                : 'Threshold ${item.lowStockThreshold} ${item.unit}.',
            style: AppText.caption,
          ),
          if (item.location?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('Kept at ${item.location}', style: AppText.caption),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.marigoldTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.marigold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unconfirmed draft',
              style: AppText.cardTitle.copyWith(color: AppColors.marigoldText)),
          const SizedBox(height: 6),
          Text(
            'This record was created by completing a purchase. Confirming it '
            'makes it usable for movements — it does not add stock again.',
            style: AppText.caption.copyWith(color: AppColors.marigoldText),
          ),
          if (onConfirm != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onConfirm,
              child: const Text('Confirm this item'),
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
      return Text(error!, style: AppText.caption.copyWith(color: AppColors.brick));
    }
    if (movements == null) {
      return const Text('Loading…', style: AppText.caption);
    }
    if (movements!.isEmpty) {
      return const Text('No movements recorded yet.', style: AppText.caption);
    }

    final ordered = [...movements!]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: [
        for (final movement in ordered) ...[
          _MovementRow(movement: movement),
          if (movement != ordered.last) const Divider(height: 18),
        ],
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final incoming = movement.isIncoming;
    final color = incoming ? AppColors.sageTealText : AppColors.brick;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(movement.type.label,
                      style:
                          AppText.caption.copyWith(fontWeight: FontWeight.w500)),
                  if (movement.isFromPurchase) ...[
                    const SizedBox(width: 6),
                    const Text(
                      'from a purchase',
                      style: TextStyle(
                        fontFamily: AppText.bodyFamily,
                        fontSize: 10,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
              if (movement.reason?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(movement.reason!, style: AppText.caption),
              ],
              const SizedBox(height: 2),
              Text(
                '${movement.createdAt.toLocal().year}-'
                '${movement.createdAt.toLocal().month.toString().padLeft(2, '0')}-'
                '${movement.createdAt.toLocal().day.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ),
        // The sign is the point of a ledger row, so it is never dropped.
        Text(
          '${incoming ? '+' : ''}${movement.changeQty}',
          style: AppText.moneySmall.copyWith(color: color),
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
    final events =
        context.watch<AppState>().events.where((e) => e.remoteId != null).toList();
    final projected = _projected;

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
              Text('Move ${widget.item.itemName}', style: AppText.cardTitle),
              const SizedBox(height: 2),
              Text(
                '${widget.item.quantity} ${widget.item.unit} in stock now.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),

              const Text('What happened', style: AppText.caption),
              const SizedBox(height: 6),
              LabeledDropdown<InventoryMovementType>(
                value: _type,
                hint: 'Select',
                items: [
                  for (final t in selectableMovementTypes)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 4),
              Text(
                _type.hint,
                style: const TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 14),

              const Text('Event', style: AppText.caption),
              const SizedBox(height: 6),
              LabeledDropdown<String>(
                value: _eventId,
                hint: 'Select an event',
                items: [
                  for (final e in events)
                    DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              const SizedBox(height: 14),

              Text('How many ${widget.item.unit}', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _countController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  helperText: _type == InventoryMovementType.adjustment
                      // The one case where the user genuinely picks the
                      // direction, so a minus is meaningful here.
                      ? 'Use a minus for a downward correction.'
                      : 'A positive count — the direction follows from '
                          'what happened.',
                ),
              ),
              if (projected != null) ...[
                const SizedBox(height: 6),
                Text(
                  projected < 0
                      ? 'That would leave $projected — stock cannot go below '
                          'zero.'
                      : 'Stock would become $projected ${widget.item.unit}.',
                  style: AppText.caption.copyWith(
                    color: projected < 0 ? AppColors.brick : AppColors.inkMuted,
                  ),
                ),
              ],
              const SizedBox(height: 14),

              const Text('Reason', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLength: InventoryService.maxReasonLength,
                decoration: const InputDecoration(
                  hintText: 'Why this is being moved',
                ),
              ),

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

              const SizedBox(height: 16),
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
                    : const Text('Record movement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
