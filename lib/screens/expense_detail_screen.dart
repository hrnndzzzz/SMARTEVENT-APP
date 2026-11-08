import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'capture_screen.dart';
import 'complete_purchase_screen.dart';
import '../theme/peso.dart';
import '../widgets/brut_date_picker.dart';
import '../widgets/event_picker_items.dart';
import '../widgets/last_change_note.dart';
import '../widgets/stored_image.dart';

/// One expense in full: amounts, the OCR reading, any flag, the itemized
/// lines, the review decision, and the entry point to purchase completion.
///
/// Two things this screen is careful about:
///   * OCR values and flags are always shown, never quietly reconciled.
///   * Approval and purchase completion are separate. An approved expense
///     has moved no stock until the purchase is recorded.
class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({super.key, required this.expense});

  final ExpenseEntry expense;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  List<ExpenseLine>? _lines;
  String? _linesError;
  bool _loadingLines = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLines());
  }

  Future<void> _loadLines() async {
    if (!mounted) return;
    setState(() {
      _loadingLines = true;
      _linesError = null;
    });

    final outcome = await context.read<AppState>().loadExpenseLines(
      widget.expense,
    );

    if (!mounted) return;
    setState(() {
      _loadingLines = false;
      _lines = outcome.lines;
      _linesError = outcome.error;
    });
  }

  /// Only asset lines can be confirmed as received stock.
  List<ExpenseLine> get _assetLines => [
    ...?_lines?.where((line) => line.isAsset),
  ];

  Future<void> _openCompletePurchase() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CompletePurchaseScreen(
          expense: widget.expense,
          assetLines: _assetLines,
        ),
      ),
    );
    if (completed == true && mounted) await _loadLines();
  }

  /// Edits go back to the list: this screen shows the record it was opened
  /// with, so staying would show the old figures.
  Future<void> _edit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final saved = await BrutSheet.show<bool>(
      context,
      builder: (_) => _EditExpenseSheet(expense: widget.expense),
    );
    if (saved != true || !mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Expense updated.')));
    navigator.pop();
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.expense.vendor}"?'),
        content: const Text(
          'It is removed for everyone. Only a pending expense with no '
          'receipt can be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await context.read<AppState>().deleteExpense(widget.expense);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Expense deleted.')),
    );
    if (error == null) navigator.pop();
  }

  /// A receipt photo for an expense saved without one — including a proof
  /// photo that failed to attach when it was saved.
  Future<void> _attachPhoto() async {
    final result = await Navigator.of(context).push<CaptureResult>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
    if (!mounted) return;
    ({List<int> bytes, String filename})? photo;
    switch (result) {
      case CapturedReceipt(:final bytes, :final filename):
        photo = (bytes: bytes, filename: filename);
      case GalleryRequested():
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked != null) {
          photo = (bytes: await picked.readAsBytes(), filename: picked.name);
        }
      case null:
        break;
    }
    if (photo == null || !mounted) return;
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await app.uploadExpenseReceipt(
      widget.expense,
      bytes: photo.bytes,
      filename: photo.filename,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Photo attached.')));
    if (error == null) {
      await app.loadExpenses();
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final remote = expense.remote;
    final app = context.watch<AppState>();

    // Own approved expense, with at least one asset line to confirm, and
    // only for whoever the server says may record money. The API
    // re-checks ownership regardless.
    final canComplete =
        !context.watch<AppState>().isOfflineViewing &&
        expense.canStartPurchaseCompletion &&
        app.mayRecordFinance &&
        _assetLines.isNotEmpty;

    // Whoever recorded it may still change it while it waits for review.
    // The demo's own rows carry no record of who made them.
    final mine = remote == null
        ? app.isDemoMode
        : remote.recordedBy == app.currentAccount?.id;
    final canChange =
        !app.isOfflineViewing &&
        app.mayRecordFinance &&
        expense.status == ExpenseStatus.pending &&
        mine;
    final hasReceipt = remote?.hasReceipt ?? false;

    return BrutScreen(
      header: BrutHeader(
        eyebrow: '${expense.category} · ${peso(expense.amount)}',
        title: expense.vendor,
        tone: expenseStatusTone(expense.status),
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusRow(expense: expense),
          if (expense.remoteId case final id?) ...[
            const SizedBox(height: 10),
            LastChangeNote(area: 'finance', entityId: id),
          ],
          if (expense.isFlagged) ...[
            const SizedBox(height: 14),
            _FlagCard(reason: expense.flagReason),
          ],
          if (remote != null) ...[
            const SizedBox(height: 14),
            _OcrCard(expense: remote),
          ],
          const SizedBox(height: 14),
          _LinesCard(
            lines: _lines,
            error: _linesError,
            loading: _loadingLines,
            onRetry: _loadLines,
          ),
          if (remote != null && remote.isPurchaseCompleted) ...[
            const SizedBox(height: 14),
            _PurchaseCard(expense: remote),
          ],
          if (canChange) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: BrutButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    tone: BrutTone.neutral,
                    onPressed: _edit,
                  ),
                ),
                if (!hasReceipt) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: BrutButton(
                      label: 'Delete',
                      icon: Icons.delete_outline,
                      tone: BrutTone.coral,
                      onPressed: _delete,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (hasReceipt)
              const Text(
                'It has a receipt, so it cannot be deleted. Ask a reviewer '
                'to reject it instead.',
                style: AppText.caption,
                textAlign: TextAlign.center,
              )
            else if (!app.isDemoMode)
              BrutButton(
                label: 'Attach a receipt photo',
                icon: Icons.add_a_photo_outlined,
                tone: BrutTone.neutral,
                onPressed: _attachPhoto,
              ),
          ],
          if (canComplete) ...[
            const SizedBox(height: 20),
            BrutButton(
              label: 'Complete purchase',
              icon: Icons.local_shipping_outlined,
              tone: BrutTone.mint,
              size: BrutSize.large,
              onPressed: _openCompletePurchase,
            ),
            const SizedBox(height: 8),
            const Text(
              'Approval alone does not add stock. Recording payment '
              'and delivery does, once.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ] else if (expense.isPurchaseCompleted) ...[
            const SizedBox(height: 20),
            const BrutInlineMessage(
              tone: BrutTone.mint,
              icon: Icons.inventory_2_outlined,
              text:
                  'This purchase has already been completed. '
                  'Stock was added once and cannot be added again.',
            ),
          ],
        ],
      ),
    );
  }
}

/// One mapping from expense status to meaning, shared with the dashboard
/// so a status can never be green in one list and yellow in another.
BrutTone expenseStatusTone(ExpenseStatus status) => switch (status) {
  ExpenseStatus.approved => BrutTone.mint,
  ExpenseStatus.rejected => BrutTone.coral,
  ExpenseStatus.pending => BrutTone.sun,
};

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.expense});

  final ExpenseEntry expense;

  @override
  Widget build(BuildContext context) {
    final label = switch (expense.status) {
      ExpenseStatus.approved => 'Approved',
      ExpenseStatus.rejected => 'Rejected',
      ExpenseStatus.pending => 'Awaiting review',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        BrutBadge(label: label, tone: expenseStatusTone(expense.status)),
        if (expense.isPurchaseCompleted)
          const BrutBadge(label: 'Purchase completed', tone: BrutTone.mint),
        if (expense.reviewedBy != null)
          BrutBadge(label: 'Reviewed by ${expense.reviewedBy}', mono: true),
      ],
    );
  }
}

/// A flag is a prompt to look, not an accusation. The wording stays neutral
/// deliberately.
class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: BrutTone.sun,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: context.palette.ink),
              const SizedBox(width: 8),
              Text('Flagged for review', style: AppText.cardTitle),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason?.isNotEmpty == true
                ? reason!
                : 'The backend flagged this expense but gave no reason.',
            style: AppText.body.copyWith(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// What OCR read, next to what was confirmed. Shown even when they agree,
/// so a mismatch is never the only time these appear.
class _OcrCard extends StatelessWidget {
  const _OcrCard({required this.expense});

  final RemoteExpense expense;

  @override
  Widget build(BuildContext context) {
    final hasAnything =
        expense.ocrMerchant != null ||
        expense.ocrDate != null ||
        expense.ocrAmount != null ||
        expense.hasReceipt;

    if (!hasAnything) return const SizedBox.shrink();

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Receipt reading'),
          const SizedBox(height: 12),
          BrutDetailRow('Merchant', expense.ocrMerchant ?? 'Not read'),
          const SizedBox(height: 8),
          BrutDetailRow('Date', expense.ocrDate ?? 'Not read'),
          const SizedBox(height: 8),
          BrutDetailRow(
            'Amount',
            expense.ocrAmount == null
                ? 'Not read'
                : '${peso(expense.ocrAmount!)}',
            mono: expense.ocrAmount != null,
          ),
          if (expense.ocrAmountDiffers) ...[
            const SizedBox(height: 12),
            BrutInlineMessage(
              tone: BrutTone.sun,
              icon: Icons.priority_high,
              text:
                  'This differs from the recorded total of '
                  '${peso(expense.amount)}.',
            ),
          ],
          if (expense.hasReceipt) ...[
            const SizedBox(height: 10),
            Text(
              'Receipt attached. Event, amount and date are locked while it '
              'is recorded.',
              style: AppText.caption.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: 12),
            // The scan that produced the figures above, so the reading
            // can be checked against the paper rather than trusted.
            StoredImage(reference: expense.receiptUrl!, height: 240),
          ],
        ],
      ),
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({
    required this.lines,
    required this.error,
    required this.loading,
    required this.onRetry,
  });

  final List<ExpenseLine>? lines;
  final String? error;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(
            'Line items',
            aside: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: BrutSpinner(size: 14),
                  )
                : BrutIconButton(
                    icon: Icons.refresh,
                    label: 'Reload line items',
                    size: 30,
                    onPressed: onRetry,
                  ),
          ),
          const SizedBox(height: 12),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    if (error != null) {
      return BrutInlineMessage(text: error!, tone: BrutTone.coral);
    }
    if (lines == null) {
      return const Text('Loading…', style: AppText.caption);
    }
    if (lines!.isEmpty) {
      // Line items are optional, so none is a real answer, not a failure.
      return const Text(
        'This expense was recorded as a single total, with no itemized '
        'breakdown.',
        style: AppText.caption,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines!) ...[
          _LineRow(line: line),
          if (line != lines!.last) const Divider(height: 20),
        ],
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final ExpenseLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              MonoLabel(
                '${line.quantity} ${line.unit} · '
                '${line.category?.label ?? 'Unclassified'}',
              ),
              if (line.isStocked) ...[
                const SizedBox(height: 6),
                const BrutBadge(label: 'In inventory', tone: BrutTone.mint),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        // The line total, already multiplied out — not a unit price.
        Text('${peso(line.amount)}', style: AppText.number),
      ],
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({required this.expense});

  final RemoteExpense expense;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: BrutTone.mint,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Purchase completed'),
          const SizedBox(height: 12),
          BrutDetailRow('Vendor', expense.purchaseVendor ?? '—'),
          const SizedBox(height: 8),
          BrutDetailRow(
            'Paid',
            expense.paidAmount == null ? '—' : '${peso(expense.paidAmount!)}',
            mono: expense.paidAmount != null,
          ),
          const SizedBox(height: 8),
          BrutDetailRow('Method', expense.paymentMethod ?? '—'),
          const SizedBox(height: 8),
          BrutDetailRow('Reference', expense.paymentReference ?? '—'),
          const SizedBox(height: 8),
          BrutDetailRow('Paid on', _date(expense.paidOn), mono: true),
          const SizedBox(height: 8),
          BrutDetailRow('Received on', _date(expense.receivedOn), mono: true),
        ],
      ),
    );
  }

  static String _date(DateTime? value) => value == null
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}'
            '-${value.day.toString().padLeft(2, '0')}';
}

/// Changing your own pending expense.
///
/// Event, amount and date are shown only when no receipt is attached: once
/// one is, the server keeps them as the receipt says.
class _EditExpenseSheet extends StatefulWidget {
  const _EditExpenseSheet({required this.expense});

  final ExpenseEntry expense;

  @override
  State<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends State<_EditExpenseSheet> {
  late final RemoteExpense? _remote = widget.expense.remote;
  late final _description = TextEditingController(
    text: widget.expense.vendor,
  );
  late final _amount = TextEditingController(
    text: MoneyInput.fromDouble(widget.expense.amount),
  );
  late String? _categoryId = _remote?.categoryId;
  late String? _eventId = _remote?.eventId;
  late DateTime? _date = _remote?.expenseDate;
  bool _saving = false;
  String? _error;

  bool get _locked => _remote?.hasReceipt ?? false;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await BrutDatePicker.show(
      context,
      initial: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      title: 'When was this spent?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Enter what this expense was for.');
      return;
    }
    final amountProblem = _locked ? null : MoneyInput.validate(_amount.text);
    if (amountProblem != null) {
      setState(() => _error = amountProblem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final remote = _remote;
    final amount = _locked ? null : MoneyInput.normalize(_amount.text);
    // Only what changed, so a locked field is never sent back.
    final error = await context.read<AppState>().updateExpense(
      widget.expense,
      description: description == widget.expense.vendor ? null : description,
      categoryId: _categoryId == remote?.categoryId ? null : _categoryId,
      amount: amount == MoneyInput.fromDouble(widget.expense.amount)
          ? null
          : amount,
      expenseDate: _locked || _date == remote?.expenseDate ? null : _date,
      eventId: _locked || _eventId == remote?.eventId ? null : _eventId,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return BrutSheet(
      title: 'Edit expense',
      footer: BrutButton(
        label: 'Save changes',
        size: BrutSize.large,
        busy: _saving,
        busyLabel: 'Saving…',
        onPressed: _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutTextField(
            label: 'Description',
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          BrutDropdown<String>(
            label: 'Category',
            value: _categoryId,
            hint: 'Select a category',
            items: [
              for (final c in app.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
          ),
          if (_locked) ...[
            const SizedBox(height: 14),
            const Text(
              'A receipt is attached, so the amount, date and event stay as '
              'it says.',
              style: AppText.caption,
            ),
          ] else ...[
            const SizedBox(height: 14),
            BrutTextField(
              label: 'Total amount',
              controller: _amount,
              prefixIcon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 14),
            BrutDateField(
              label: 'Date',
              value: _date,
              hint: 'Select a date',
              onTap: _pickDate,
            ),
            const SizedBox(height: 14),
            BrutDropdown<String>(
              label: 'Event',
              value: _eventId,
              hint: 'No event',
              items: eventPickerItems(app.events, keep: _eventId),
              onChanged: (v) => setState(() => _eventId = v),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          ],
        ],
      ),
    );
  }
}
