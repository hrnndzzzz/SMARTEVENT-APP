import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class _Approval {
  final String title;
  final String org;
  final String amount;

  _Approval({required this.title, required this.org, required this.amount});
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final List<_Approval> _pending = [
    _Approval(
      title: 'Leadership Summit 2026 — Budget Proposal',
      org: 'Engineering Soc.',
      amount: '₱8,200.00',
    ),
    _Approval(
      title: 'CITE Sports Fest — Cash Advance',
      org: 'CITE Student Council',
      amount: '₱1,500.00',
    ),
  ];

  final List<_Approval> _handled = [];

  void _decide(_Approval req, {required bool approved}) {
    setState(() {
      _pending.remove(req);
      _handled.insert(0, req);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${req.title} — ${approved ? 'Approved' : 'Rejected'}')),
    );
  }

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
                initials: 'SA',
                subtitle: 'System Administrator',
                subtitleBg: const Color(0xFFE8ECF3),
                subtitleColor: AppColors.indigo,
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SA',
                      name: 'Admin User',
                      role: 'System Administrator',
                    ),
                  ),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    const _QuickActionsGrid(),
                    const SizedBox(height: 18),
                    Text('Pending approvals (${_pending.length})', style: AppText.cardTitle),
                    const SizedBox(height: 10),
                    if (_pending.isEmpty)
                      const _EmptyState(text: 'No pending approvals. All caught up.')
                    else
                      for (final req in _pending) ...[
                        _ApprovalCard(
                          approval: req,
                          onApprove: () => _decide(req, approved: true),
                          onReject: () => _decide(req, approved: false),
                        ),
                        const SizedBox(height: 10),
                      ],
                    if (_handled.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('Recently handled', style: AppText.caption),
                      const SizedBox(height: 8),
                      for (final req in _handled) ...[
                        _HandledRow(approval: req),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: const [
        _ActionTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Set Category Budget',
          accent: AppColors.indigo,
        ),
        _ActionTile(
          icon: Icons.fact_check_outlined,
          label: 'Approve / Reject Requests',
          accent: AppColors.marigold,
        ),
        _ActionTile(
          icon: Icons.description_outlined,
          label: 'Generate Reports',
          accent: AppColors.sageTeal,
        ),
        _ActionTile(
          icon: Icons.bar_chart_outlined,
          label: 'View Analytics',
          accent: AppColors.brick,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _ActionTile({required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: accent, size: 20),
          Text(
            label,
            style: AppText.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final _Approval approval;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.approval,
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
            Text(approval.title, style: AppText.cardTitle),
            const SizedBox(height: 4),
            Text(approval.org, style: AppText.caption),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  approval.amount,
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
  final _Approval approval;
  const _HandledRow({required this.approval});

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
              '${approval.title} · ${approval.org}',
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