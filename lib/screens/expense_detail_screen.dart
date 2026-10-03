import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import 'complete_purchase_screen.dart';

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

    final outcome =
        await context.read<AppState>().loadExpenseLines(widget.expense);

    if (!mounted) return;
    setState(() {
      _loadingLines = false;
      _lines = outcome.lines;
      _linesError = outcome.error;
    });
  }

  /// Only asset lines can be confirmed as received stock.
  List<ExpenseLine> get _assetLines =>
      [...?_lines?.where((line) => line.isAsset)];

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

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final remote = expense.remote;
    final role = context.watch<AppState>().currentRole;

    // Own approved expense or an administrator, with at least one asset
    // line to confirm. The API re-checks ownership regardless.
    final canComplete = expense.canStartPurchaseCompletion &&
        (role?.canRecordFinance ?? false) &&
        _assetLines.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              eyebrow:
                  '${expense.category} · ₱${expense.amount.toStringAsFixed(2)}',
              title: expense.vendor,
              tone: expenseStatusTone(expense.status),
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusRow(expense: expense),
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
                        text: 'This purchase has already been completed. '
                            'Stock was added once and cannot be added again.',
                      ),
                    ],
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
              const Icon(Icons.flag_outlined, size: 18, color: AppColors.ink),
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
    final hasAnything = expense.ocrMerchant != null ||
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
          detailRow('Merchant', expense.ocrMerchant ?? 'Not read'),
          const SizedBox(height: 8),
          detailRow('Date', expense.ocrDate ?? 'Not read'),
          const SizedBox(height: 8),
          detailRow(
            'Amount',
            expense.ocrAmount == null
                ? 'Not read'
                : '₱${expense.ocrAmount!.toStringAsFixed(2)}',
            mono: expense.ocrAmount != null,
          ),
          if (expense.ocrAmountDiffers) ...[
            const SizedBox(height: 12),
            BrutInlineMessage(
              tone: BrutTone.sun,
              icon: Icons.priority_high,
              text: 'This differs from the recorded total of '
                  '₱${expense.amount.toStringAsFixed(2)}.',
            ),
          ],
          if (expense.hasReceipt) ...[
            const SizedBox(height: 10),
            Text(
              'Receipt attached. Event, amount and date are locked while it '
              'is recorded.',
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label on the left, its value right-aligned on the right. Shared by
/// the detail cards on this screen so their columns line up.
Widget detailRow(String label, String value, {bool mono = false}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: MonoLabel(label)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: mono
              ? AppText.number
              : AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
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
                    child: CircularProgressIndicator(strokeWidth: 2),
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
        Text('₱${line.amount.toStringAsFixed(2)}', style: AppText.number),
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
          detailRow('Vendor', expense.purchaseVendor ?? '—'),
          const SizedBox(height: 8),
          detailRow(
            'Paid',
            expense.paidAmount == null
                ? '—'
                : '₱${expense.paidAmount!.toStringAsFixed(2)}',
            mono: expense.paidAmount != null,
          ),
          const SizedBox(height: 8),
          detailRow('Method', expense.paymentMethod ?? '—'),
          const SizedBox(height: 8),
          detailRow('Reference', expense.paymentReference ?? '—'),
          const SizedBox(height: 8),
          detailRow('Paid on', _date(expense.paidOn), mono: true),
          const SizedBox(height: 8),
          detailRow('Received on', _date(expense.receivedOn), mono: true),
        ],
      ),
    );
  }

  static String _date(DateTime? value) => value == null
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}'
          '-${value.day.toString().padLeft(2, '0')}';
}
