import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One receipt, what it resembles, and the decision.
///
/// The comparison is the point: a reviewer cannot judge a similarity flag
/// without seeing both sides, so the similar receipts are loaded and shown
/// rather than summarised as a count.
///
/// Detection results are presented as detection results. Same merchant,
/// same amount and a nearby date is a reason to look, not a finding.
class ReceiptReviewScreen extends StatefulWidget {
  const ReceiptReviewScreen({super.key, required this.receipt});

  final Receipt receipt;

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  final _reasonController = TextEditingController();

  List<Receipt>? _similar;
  String? _similarError;
  bool _loadingSimilar = false;

  bool _submitting = false;
  String? _error;

  late Receipt _receipt = widget.receipt;

  @override
  void initState() {
    super.initState();
    if (_receipt.hasSimilar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSimilar());
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadSimilar() async {
    setState(() {
      _loadingSimilar = true;
      _similarError = null;
    });

    final outcome = await context.read<AppState>().loadSimilarTo(_receipt);

    if (!mounted) return;
    setState(() {
      _loadingSimilar = false;
      _similar = outcome.found;
      _similarError = outcome.error;
    });
  }

  Future<void> _decide(ReceiptDecision decision) async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await context.read<AppState>().reviewReceipt(
          _receipt,
          decision: decision,
          reason: _reasonController.text,
        );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    final updated = context
        .read<AppState>()
        .receipts
        .where((r) => r.id == _receipt.id)
        .firstOrNull;

    setState(() {
      _submitting = false;
      if (updated != null) _receipt = updated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          decision == ReceiptDecision.cleared
              ? 'Receipt cleared.'
              : 'Receipt rejected.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().currentRole;

    // Only an independent reviewer decides, and only while it is pending.
    // The API also refuses the person who recorded it.
    final canReview = _receipt.isAwaitingReview && (role?.canReview ?? false);

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
              const Text(
                'Receipt',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),

              _StatusCard(receipt: _receipt),
              const SizedBox(height: 14),
              _DetailsCard(receipt: _receipt, title: 'This receipt'),

              if (_receipt.hasSimilar) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Similar receipts', style: AppText.cardTitle),
                    ),
                    if (_loadingSimilar)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Matched on merchant, amount and a nearby date. Similar is '
                  'not the same as duplicated — compare them before deciding.',
                  style: AppText.caption,
                ),
                const SizedBox(height: 10),
                if (_similarError != null)
                  Text(
                    _similarError!,
                    style: AppText.caption.copyWith(color: AppColors.brick),
                  )
                else if (_similar != null && _similar!.isEmpty)
                  const Text(
                    'The similar receipts are outside what your account can '
                    'see, so they cannot be shown here.',
                    style: AppText.caption,
                  )
                else
                  for (final other in _similar ?? const <Receipt>[]) ...[
                    _DetailsCard(receipt: other, title: 'Compared with'),
                    const SizedBox(height: 10),
                  ],
              ],

              if (canReview) ...[
                const SizedBox(height: 18),
                const Text('Your decision', style: AppText.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'A reason of at least ${ReceiptService.minReasonLength} '
                  'characters is required, and the decision is final.',
                  style: AppText.caption,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Why this is or is not a duplicate',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.brick.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _error!,
                      style: AppText.caption.copyWith(color: AppColors.brick),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => _decide(ReceiptDecision.rejected),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppColors.brick,
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submitting
                            ? null
                            : () => _decide(ReceiptDecision.cleared),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Clear'),
                      ),
                    ),
                  ],
                ),
              ] else if (_receipt.isAwaitingReview) ...[
                const SizedBox(height: 18),
                const Text(
                  'This receipt is waiting on an Adviser or Admin to decide.',
                  style: AppText.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (receipt.reviewStatus) {
      ReceiptReviewStatus.clear => (AppColors.inkMuted, AppColors.trackBg),
      ReceiptReviewStatus.pending => (AppColors.marigoldText, AppColors.marigoldTint),
      ReceiptReviewStatus.cleared => (AppColors.sageTealText, AppColors.sageTealTint),
      ReceiptReviewStatus.rejected => (AppColors.brick, const Color(0xFFFBEAE7)),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(receipt.reviewStatus.label,
              style: AppText.cardTitle.copyWith(color: fg)),
          const SizedBox(height: 4),
          // Spelling out what the status actually does to the transaction,
          // since "pending" alone does not explain a blocked approval.
          Text(receipt.reviewStatus.consequence,
              style: AppText.caption.copyWith(color: fg)),
          if (receipt.reviewReason?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text('Reason given: “${receipt.reviewReason}”',
                style: AppText.caption.copyWith(color: fg)),
          ],
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.receipt, required this.title});

  final Receipt receipt;
  final String title;

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
          Text(title, style: AppText.cardTitle),
          const SizedBox(height: 10),
          _row('Merchant', receipt.merchant ?? 'Not recorded'),
          const SizedBox(height: 6),
          _row('Amount', '₱${receipt.amount.toStringAsFixed(2)}'),
          const SizedBox(height: 6),
          _row(
            'Issued',
            '${receipt.issuedOn.year}-'
                '${receipt.issuedOn.month.toString().padLeft(2, '0')}-'
                '${receipt.issuedOn.day.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 6),
          _row('Reference', receipt.receiptNumber ?? 'Not recorded'),
          const SizedBox(height: 6),
          _row('Purpose', receipt.purpose),
          const SizedBox(height: 6),
          _row('Attached to', receipt.isForExpense ? 'An expense' : 'An income'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label, style: AppText.caption)),
        Expanded(child: Text(value, style: AppText.body)),
      ],
    );
  }
}
