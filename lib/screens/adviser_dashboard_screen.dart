import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class AdviserDashboardScreen extends StatelessWidget {
  const AdviserDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                initials: 'FA',
                subtitle: 'Faculty Adviser',
                subtitleBg: AppColors.sageTealTint,
                subtitleColor: AppColors.sageTealText,
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'FA',
                      name: 'Engr Bañares',
                      role: 'Faculty Adviser',
                    ),
                  ),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        const _BalanceOverviewCard(),
                        const SizedBox(height: 18),
                        Text('Pending requests (${app.pendingRequests.length})', style: AppText.cardTitle),
                        const SizedBox(height: 10),
                        if (app.pendingRequests.isEmpty)
                          const _EmptyState(text: 'No pending requests. All caught up.')
                        else
                          for (final req in app.pendingRequests) ...[
                            _RequestCard(
                              request: req,
                              onApprove: () => app.decideRequest(req, approved: true),
                              onReject: () => app.decideRequest(req, approved: false),
                            ),
                            const SizedBox(height: 10),
                          ],
                        if (app.handledRequests.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text('Recently handled', style: AppText.caption),
                          const SizedBox(height: 8),
                          for (final req in app.handledRequests) ...[
                            _HandledRow(request: req),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceOverviewCard extends StatelessWidget {
  const _BalanceOverviewCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Org balance overview', style: AppText.cardTitle),
            const SizedBox(height: 12),
            _row('CITE Student Council', '₱2,850.00'),
            const SizedBox(height: 8),
            _row('Engineering Soc.', '₱1,240.00'),
            const SizedBox(height: 8),
            _row('IT Society', '₱4,910.00'),
          ],
        ),
      ),
    );
  }

  Widget _row(String org, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(org, style: AppText.body.copyWith(fontSize: 12)),
        Text(
          amount,
          style: const TextStyle(
            fontFamily: AppText.monoFamily,
            fontWeight: FontWeight.w500,
            fontSize: 13,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final PendingRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.marigoldTint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    request.type,
                    style: const TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.marigoldText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(request.title, style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(request.org, style: AppText.caption),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  request.amount,
                  style: const TextStyle(
                    fontFamily: AppText.monoFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        side: const BorderSide(color: AppColors.brick, width: 0.8),
                        foregroundColor: AppColors.brick,
                      ),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      ),
                      child: const Text('Approve', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HandledRow extends StatelessWidget {
  final PendingRequest request;
  const _HandledRow({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: AppColors.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${request.title} · ${request.org}',
              style: AppText.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Text(text, style: AppText.caption),
    );
  }
}