import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

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
                initials: 'SO',
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SO',
                      name: 'Juan Dela Cruz',
                      role: 'CITE Dept Officer',
                    ),
                  ),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Inventory & Equipment',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text('Track and manage campus resources.', style: AppText.caption),
              const SizedBox(height: 14),
              const _LowStockBanner(),
              const SizedBox(height: 12),
              const _SearchField(),
              const SizedBox(height: 12),
              const _CategoryChips(),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: const [
                    _InventoryItemCard(
                      icon: Icons.cable,
                      name: 'HDMI Cables (4K 10m)',
                      description: 'High-speed AV connectivity.',
                      qty: 1,
                      statusLabel: 'Low Stock',
                      statusColor: AppColors.brick,
                      statusBg: Color(0xFFFBEAE7),
                      statusIcon: Icons.warning_amber_rounded,
                      tagColor: AppColors.brick,
                      showRestock: true,
                    ),
                    SizedBox(height: 10),
                    _InventoryItemCard(
                      icon: Icons.campaign_outlined,
                      name: 'PA Sound System Set',
                      description: 'Includes 2 speakers, mixer, and wireless mics.',
                      qty: 4,
                      statusLabel: 'Operational',
                      statusColor: AppColors.sageTealText,
                      statusBg: AppColors.sageTealTint,
                      statusIcon: Icons.check_circle_outline,
                      tagColor: AppColors.sageTeal,
                      showRestock: false,
                    ),
                    SizedBox(height: 16),
                    Text('Recent transactions', style: AppText.caption),
                    SizedBox(height: 8),
                    _RecentTransactionsList(),
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

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.marigoldTint,
        border: Border.all(color: const Color(0xFFE3D6B4), width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.marigoldText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2 items below minimum threshold',
                  style: TextStyle(
                    fontFamily: AppText.headerFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.marigoldText,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Immediate action needed to ensure event continuity.',
                  style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 11, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, size: 18, color: AppColors.inkMuted),
          SizedBox(width: 8),
          Text('Search inventory...', style: TextStyle(color: AppColors.inkFaint, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All Items', selected: true),
          const SizedBox(width: 8),
          _chip('In-Stock'),
          const SizedBox(width: 8),
          _chip('Issued'),
        ],
      ),
    );
  }

  Widget _chip(String label, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.indigo : AppColors.surface,
        border: selected ? null : Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected ? Colors.white : AppColors.ink,
        ),
      ),
    );
  }
}

class _InventoryItemCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final int qty;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;
  final IconData statusIcon;
  final Color tagColor;
  final bool showRestock;

  const _InventoryItemCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.qty,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
    required this.statusIcon,
    required this.tagColor,
    required this.showRestock,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F2EC),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 18, color: AppColors.ink),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 11, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontFamily: AppText.bodyFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(name, style: AppText.cardTitle),
              const SizedBox(height: 2),
              Text(description, style: AppText.caption),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$qty',
                      style: const TextStyle(
                        fontFamily: AppText.monoFamily,
                        fontWeight: FontWeight.w500,
                        fontSize: 20,
                        color: AppColors.ink,
                      ),
                    ),
                    const TextSpan(
                      text: ' Qty available',
                      style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)),
                      child: const Text('Issue Item', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  if (showRestock) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)),
                        child: const Text('Restock', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 12,
          bottom: 12,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentTransactionsList extends StatelessWidget {
  const _RecentTransactionsList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _row(
            icon: Icons.arrow_outward,
            iconBg: const Color(0xFFF4F2EC),
            iconColor: AppColors.ink,
            text: 'PA System — checked out by J. Doe',
            time: '2h ago',
          ),
          const Divider(height: 1, color: AppColors.border),
          _row(
            icon: Icons.reply,
            iconBg: AppColors.sageTealTint,
            iconColor: AppColors.sageTealText,
            text: 'Projector Screen — returned by S. Smith',
            time: '5h ago',
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String text,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppText.body.copyWith(fontSize: 13)),
                const SizedBox(height: 1),
                Text(time, style: AppText.moneySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}