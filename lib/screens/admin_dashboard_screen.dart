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

  Future<void> _setCategoryBudget() async {
    final categories = ['Equipment', 'Venue', 'Catering', 'Marketing'];
    String selected = categories.first;
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set Category Budget', style: AppText.cardTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category', style: AppText.caption),
              const SizedBox(height: 6),
              DropdownButton<String>(
                value: selected,
                isExpanded: true,
                items: [
                  for (final c in categories) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setDialogState(() => selected = v!),
              ),
              const SizedBox(height: 14),
              const Text('Amount (₱)', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '0.00'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$selected budget updated to ₱${controller.text.isEmpty ? '0.00' : controller.text}')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _generateReports() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating org-wide financial summary...')),
    );
  }

  Future<void> _viewAnalytics() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Org-Wide Analytics', style: AppText.cardTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _analyticsRow('Total budget allocated', '₱14,150.00'),
              _analyticsRow('Total expended (all orgs)', '₱6,850.00'),
              _analyticsRow('Overall utilization', '48%'),
              const SizedBox(height: 12),
              const Text('By category', style: AppText.caption),
              const SizedBox(height: 8),
              _analyticsRow('Equipment', '45%', indent: true),
              _analyticsRow('Venue', '30%', indent: true),
              _analyticsRow('Catering', '15%', indent: true),
              _analyticsRow('Marketing', '10%', indent: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _analyticsRow(String label, String value, {bool indent = false}) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 12 : 0, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body.copyWith(fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppText.monoFamily,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
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
                    _QuickActionsRow(
                      onSetBudget: _setCategoryBudget,
                      onGenerateReports: _generateReports,
                      onViewAnalytics: _viewAnalytics,
                    ),
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

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onSetBudget;
  final VoidCallback onGenerateReports;
  final VoidCallback onViewAnalytics;

  const _QuickActionsRow({
    required this.onSetBudget,
    required this.onGenerateReports,
    required this.onViewAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Set Budget',
            accent: AppColors.indigo,
            onTap: onSetBudget,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.description_outlined,
            label: 'Reports',
            accent: AppColors.sageTeal,
            onTap: onGenerateReports,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.bar_chart_outlined,
            label: 'Analytics',
            accent: AppColors.brick,
            onTap: onViewAnalytics,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  const _ActionTile({required this.icon, required this.label, required this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
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