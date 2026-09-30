import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
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
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Receipts',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Proof of spending, and anything that looks like a duplicate.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              const _FilterBar(),
              const SizedBox(height: 12),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.receipts.isEmpty =>
                    const Center(child: CircularProgressIndicator()),
                  _ when load.hasFailed && app.receipts.isEmpty => _Retry(
                      message: load.error!,
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

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All',
            selected: all,
            onTap: () => app.applyReceiptFilter(),
          ),
          _Chip(
            label: 'Needs review',
            selected: pending,
            onTap: () => app.applyReceiptFilter(
              reviewStatus: ReceiptReviewStatus.pending,
            ),
          ),
          _Chip(
            label: 'Flagged',
            selected: flagged,
            onTap: () => app.applyReceiptFilter(flaggedOnly: true),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.indigo : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.indigo : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});

  final Receipt receipt;

  (Color, Color) get _statusColors => switch (receipt.reviewStatus) {
        ReceiptReviewStatus.clear => (AppColors.inkMuted, AppColors.trackBg),
        ReceiptReviewStatus.pending => (
            AppColors.marigoldText,
            AppColors.marigoldTint
          ),
        ReceiptReviewStatus.cleared => (
            AppColors.sageTealText,
            AppColors.sageTealTint
          ),
        ReceiptReviewStatus.rejected => (
            AppColors.brick,
            const Color(0xFFFBEAE7)
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _statusColors;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReceiptReviewScreen(receipt: receipt)),
      ),
      child: Container(
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
                Expanded(
                  child: Text(
                    receipt.merchant?.isNotEmpty == true
                        ? receipt.merchant!
                        : 'No merchant recorded',
                    style: AppText.cardTitle,
                  ),
                ),
                Text(
                  '₱${receipt.amount.toStringAsFixed(2)}',
                  style: AppText.moneySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(receipt.purpose, style: AppText.caption),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    receipt.reviewStatus.label,
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (receipt.hasSimilar)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.trackBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${receipt.similarReceiptIds.length} similar',
                      style: const TextStyle(
                        fontFamily: AppText.bodyFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                Text(
                  '${receipt.issuedOn.year}-'
                  '${receipt.issuedOn.month.toString().padLeft(2, '0')}-'
                  '${receipt.issuedOn.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontSize: 10,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final filtered = context.watch<AppState>().receiptStatusFilter != null ||
        context.watch<AppState>().receiptFlaggedOnly;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_outlined, size: 44, color: AppColors.inkFaint),
          const SizedBox(height: 14),
          Text(
            filtered ? 'Nothing matches this filter' : 'No receipts yet',
            style: AppText.cardTitle,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              filtered
                  // An empty review queue is good news, so say so.
                  ? 'Nothing is waiting on a duplicate decision.'
                  : 'Receipts appear here once they are attached to an '
                      'expense or an income.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({
    required this.message,
    required this.sessionExpired,
    required this.onRetry,
  });

  final String message;
  final bool sessionExpired;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            const Text('Could not load receipts', style: AppText.cardTitle),
            const SizedBox(height: 6),
            Text(message, style: AppText.caption, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (sessionExpired)
              const Text(
                'Sign out and sign in again to continue.',
                style: AppText.caption,
                textAlign: TextAlign.center,
              )
            else
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
