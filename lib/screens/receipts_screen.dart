import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'receipt_review_screen.dart';

/// Receipts and the duplicate-review queue.
///
/// The framing throughout is "these look alike, someone should check",
/// never "this is fraud". A flag is a prompt, and the reviewer decides.
class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadReceipts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.receiptsLoad;

    return Scaffold(
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
              const Text('Receipts', style: AppText.screenTitle),
              const SizedBox(height: 4),
              const Text(
                'Proof of spending, and anything that looks like a duplicate.',
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              const _FilterBar(),
              const SizedBox(height: 14),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.receipts.isEmpty => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  _ when load.hasFailed && app.receipts.isEmpty => BrutRetry(
                    title: 'Could not load receipts',
                    message: load.error,
                    sessionExpired: load.sessionExpired,
                    onRetry: app.loadReceipts,
                  ),
                  _ when app.receipts.isEmpty => const _Empty(),
                  _ => RefreshIndicator(
                    onRefresh: app.loadReceipts,
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: app.receipts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _ReceiptCard(receipt: app.receipts[i]),
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
    final pending = app.receiptStatusFilter == ReceiptReviewStatus.pending;
    final flagged = app.receiptFlaggedOnly;
    final all = !pending && !flagged;

    return BrutChipBar(
      children: [
        BrutChip(
          label: 'All',
          selected: all,
          onTap: () => app.applyReceiptFilter(),
        ),
        BrutChip(
          label: 'Needs review',
          selected: pending,
          onTap: () =>
              app.applyReceiptFilter(reviewStatus: ReceiptReviewStatus.pending),
        ),
        BrutChip(
          label: 'Flagged',
          selected: flagged,
          onTap: () => app.applyReceiptFilter(flaggedOnly: true),
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});

  final Receipt receipt;

  /// "Clear" means nothing looked alike, so it is deliberately the
  /// quietest state — it is not an approval anyone made.
  BrutTone get _tone => switch (receipt.reviewStatus) {
    ReceiptReviewStatus.clear => BrutTone.neutral,
    ReceiptReviewStatus.pending => BrutTone.sun,
    ReceiptReviewStatus.cleared => BrutTone.mint,
    ReceiptReviewStatus.rejected => BrutTone.coral,
  };

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptReviewScreen(receipt: receipt),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  receipt.merchant?.isNotEmpty == true
                      ? receipt.merchant!
                      : 'No merchant recorded',
                  style: AppText.cardTitle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '₱${receipt.amount.toStringAsFixed(2)}',
                style: AppText.moneyLarge.copyWith(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(receipt.purpose, style: AppText.caption),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BrutBadge(label: receipt.reviewStatus.label, tone: _tone),
              if (receipt.hasSimilar)
                BrutBadge(
                  label: '${receipt.similarReceiptIds.length} similar',
                  mono: true,
                ),
              MonoLabel(
                '${receipt.issuedOn.year}-'
                '${receipt.issuedOn.month.toString().padLeft(2, '0')}-'
                '${receipt.issuedOn.day.toString().padLeft(2, '0')}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final filtered = app.receiptStatusFilter != null || app.receiptFlaggedOnly;

    return Center(
      child: BrutEmptyState(
        icon: Icons.receipt_outlined,
        title: filtered ? 'Nothing matches this filter' : 'No receipts yet',
        hint: filtered
            // An empty review queue is good news, so say so.
            ? 'Nothing is waiting on a duplicate decision.'
            : 'Receipts appear here once they are attached to an expense '
                  'or an income.',
      ),
    );
  }
}
