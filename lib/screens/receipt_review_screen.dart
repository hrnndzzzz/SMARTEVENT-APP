import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/peso.dart';
import '../widgets/stored_image.dart';

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

    return BrutScreen(
      header: BrutHeader(
        eyebrow: 'Duplicate review',
        title: 'Receipt',
        tone: receiptStatusTone(_receipt.reviewStatus),
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusCard(receipt: _receipt),
          const SizedBox(height: 14),
          // The receipt itself. Reviewing one for a duplicate without
          // being able to look at it was asking for a judgement on two
          // rows of text.
          StoredImage(reference: _receipt.receiptUrl),
          const SizedBox(height: 14),
          _DetailsCard(receipt: _receipt, title: 'This receipt'),

          if (_receipt.hasSimilar) ...[
            const SizedBox(height: 18),
            BrutSectionTitle(
              'Similar receipts',
              aside: _loadingSimilar
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            const Text(
              'Matched on merchant, amount and a nearby date. Similar is '
              'not the same as duplicated — compare them before deciding.',
              style: AppText.caption,
            ),
            const SizedBox(height: 10),
            if (_similarError != null)
              BrutInlineMessage(text: _similarError!, tone: BrutTone.coral)
            else if (_similar != null && _similar!.isEmpty)
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.visibility_off_outlined,
                text:
                    'The similar receipts are outside what your account '
                    'can see, so they cannot be shown here.',
              )
            else
              for (final other in _similar ?? const <Receipt>[]) ...[
                _DetailsCard(receipt: other, title: 'Compared with'),
                const SizedBox(height: 10),
              ],
          ],

          if (canReview) ...[
            const SizedBox(height: 18),
            const BrutSectionTitle('Your decision'),
            const SizedBox(height: 4),
            Text(
              'A reason of at least ${ReceiptService.minReasonLength} '
              'characters is required, and the decision is final.',
              style: AppText.caption,
            ),
            const SizedBox(height: 10),
            BrutTextField(
              controller: _reasonController,
              maxLines: 3,
              hint: 'Why this is or is not a duplicate',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              BrutInlineMessage(text: _error!, tone: BrutTone.coral),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: BrutButton(
                    label: 'Reject',
                    tone: BrutTone.coral,
                    busy: _submitting,
                    onPressed: () => _decide(ReceiptDecision.rejected),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BrutButton(
                    label: 'Clear',
                    tone: BrutTone.mint,
                    busy: _submitting,
                    busyLabel: 'Saving…',
                    onPressed: () => _decide(ReceiptDecision.cleared),
                  ),
                ),
              ],
            ),
          ] else if (_receipt.isAwaitingReview) ...[
            const SizedBox(height: 18),
            const BrutInlineMessage(
              tone: BrutTone.sun,
              icon: Icons.hourglass_top,
              text:
                  'This receipt is waiting on an Adviser or Admin to '
                  'decide.',
            ),
          ],
        ],
      ),
    );
  }
}

/// One mapping from a receipt's review state to meaning. "Clear" is the
/// quietest: nothing looked alike, which is not an approval anyone made.
BrutTone receiptStatusTone(ReceiptReviewStatus status) => switch (status) {
  ReceiptReviewStatus.clear => BrutTone.neutral,
  ReceiptReviewStatus.pending => BrutTone.sun,
  ReceiptReviewStatus.cleared => BrutTone.mint,
  ReceiptReviewStatus.rejected => BrutTone.coral,
};

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: receiptStatusTone(receipt.reviewStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(receipt.reviewStatus.label, style: AppText.cardTitle),
          const SizedBox(height: 4),
          // Spelling out what the status actually does to the transaction,
          // since "pending" alone does not explain a blocked approval.
          Text(
            receipt.reviewStatus.consequence,
            style: AppText.body.copyWith(fontSize: 12.5),
          ),
          if (receipt.reviewReason?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              'Reason given: “${receipt.reviewReason}”',
              style: AppText.body.copyWith(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
              ),
            ),
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
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(title),
          const SizedBox(height: 12),
          BrutDetailRow('Merchant', receipt.merchant ?? 'Not recorded'),
          const SizedBox(height: 8),
          BrutDetailRow('Amount', '${peso(receipt.amount)}', mono: true),
          const SizedBox(height: 8),
          BrutDetailRow(
            'Issued',
            BrutDateField.format(receipt.issuedOn),
            mono: true,
          ),
          const SizedBox(height: 8),
          BrutDetailRow('Reference', receipt.receiptNumber ?? 'Not recorded'),
          const SizedBox(height: 8),
          BrutDetailRow('Purpose', receipt.purpose),
          const SizedBox(height: 8),
          BrutDetailRow(
            'Attached to',
            receipt.isForExpense ? 'An expense' : 'An income',
          ),
        ],
      ),
    );
  }
}
