import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
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

    final outcome = await context.read<AppState>().loadExpenseLines(widget.expense);

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
                expense.vendor,
                style: const TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${expense.category} · ₱${expense.amount.toStringAsFixed(2)}',
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
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
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _openCompletePurchase,
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Complete Purchase'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Approval alone does not add stock. Recording payment and '
                  'delivery does, once.',
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                ),
              ] else if (expense.isPurchaseCompleted) ...[
                const SizedBox(height: 18),
                const Text(
                  'This purchase has already been completed. Stock was added '
                  'once and cannot be added again.',
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.expense});

  final ExpenseEntry expense;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (expense.status) {
      ExpenseStatus.approved => ('Approved', AppColors.sageTealText, AppColors.sageTealTint),
      ExpenseStatus.rejected => ('Rejected', AppColors.brick, const Color(0xFFFBEAE7)),
      ExpenseStatus.pending => ('Awaiting review', AppColors.marigoldText, AppColors.marigoldTint),
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Pill(label: label, color: color, background: bg),
        if (expense.isPurchaseCompleted)
          const _Pill(
            label: 'Purchase completed',
            color: AppColors.sageTealText,
            background: AppColors.sageTealTint,
          ),
        if (expense.reviewedBy != null)
          _Pill(
            label: 'Reviewed by ${expense.reviewedBy}',
            color: AppColors.inkMuted,
            background: AppColors.trackBg,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
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
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 16, color: AppColors.marigoldText),
              const SizedBox(width: 6),
              Text(
                'Flagged for review',
                style: AppText.cardTitle.copyWith(color: AppColors.marigoldText),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason?.isNotEmpty == true
                ? reason!
                : 'The backend flagged this expense but gave no reason.',
            style: AppText.caption.copyWith(color: AppColors.marigoldText),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Receipt reading', style: AppText.cardTitle),
          const SizedBox(height: 10),
          _row('Merchant', expense.ocrMerchant ?? 'Not read'),
          const SizedBox(height: 6),
          _row('Date', expense.ocrDate ?? 'Not read'),
          const SizedBox(height: 6),
          _row(
            'Amount',
            expense.ocrAmount == null
                ? 'Not read'
                : '₱${expense.ocrAmount!.toStringAsFixed(2)}',
          ),
          if (expense.ocrAmountDiffers) ...[
            const SizedBox(height: 8),
            Text(
              'This differs from the recorded total of '
              '₱${expense.amount.toStringAsFixed(2)}.',
              style: AppText.caption.copyWith(color: AppColors.marigoldText),
            ),
          ],
          if (expense.hasReceipt) ...[
            const SizedBox(height: 8),
            Text(
              'Receipt attached. Event, amount and date are locked while it '
              'is recorded.',
              style: AppText.caption.copyWith(color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 90, child: Text(label, style: AppText.caption)),
        Expanded(child: Text(value, style: AppText.body)),
      ],
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
    return Container(
      width: double.infinity,
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
              const Expanded(child: Text('Line items', style: AppText.cardTitle)),
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    if (error != null) {
      return Text(error!, style: AppText.caption.copyWith(color: AppColors.brick));
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
          if (line != lines!.last) const Divider(height: 18),
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
              Text(line.name, style: AppText.body),
              const SizedBox(height: 2),
              Text(
                '${line.quantity} ${line.unit} · '
                '${line.category?.label ?? 'Unclassified'}',
                style: AppText.caption,
              ),
              if (line.isStocked) ...[
                const SizedBox(height: 2),
                Text(
                  'In inventory',
                  style: AppText.caption.copyWith(color: AppColors.sageTealText),
                ),
              ],
            ],
          ),
        ),
        // The line total, already multiplied out — not a unit price.
        Text('₱${line.amount.toStringAsFixed(2)}', style: AppText.moneySmall),
      ],
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({required this.expense});

  final RemoteExpense expense;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sageTealTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.sageTealBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Purchase completed',
            style: AppText.cardTitle.copyWith(color: AppColors.sageTealText),
          ),
          const SizedBox(height: 10),
          _row('Vendor', expense.purchaseVendor ?? '—'),
          const SizedBox(height: 6),
          _row('Paid', expense.paidAmount == null
              ? '—'
              : '₱${expense.paidAmount!.toStringAsFixed(2)}'),
          const SizedBox(height: 6),
          _row('Method', expense.paymentMethod ?? '—'),
          const SizedBox(height: 6),
          _row('Reference', expense.paymentReference ?? '—'),
          const SizedBox(height: 6),
          _row('Paid on', _date(expense.paidOn)),
          const SizedBox(height: 6),
          _row('Received on', _date(expense.receivedOn)),
        ],
      ),
    );
  }

  static String _date(DateTime? value) => value == null
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}'
          '-${value.day.toString().padLeft(2, '0')}';

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: AppText.caption.copyWith(color: AppColors.sageTealText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppText.body.copyWith(color: AppColors.sageTealText),
          ),
        ),
      ],
    );
  }
}
