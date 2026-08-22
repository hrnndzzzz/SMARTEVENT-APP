import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class _InventoryItem {
  final IconData icon;
  final String name;
  final String description;
  int qty;
  final int lowStockThreshold;

  _InventoryItem({
    required this.icon,
    required this.name,
    required this.description,
    required this.qty,
    this.lowStockThreshold = 2,
  });

  bool get isLowStock => qty < lowStockThreshold;
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final List<_InventoryItem> _items = [
    _InventoryItem(
      icon: Icons.cable,
      name: 'HDMI Cables (4K 10m)',
      description: 'High-speed AV connectivity.',
      qty: 1,
    ),
    _InventoryItem(
      icon: Icons.campaign_outlined,
      name: 'PA Sound System Set',
      description: 'Includes 2 speakers, mixer, and wireless mics.',
      qty: 4,
    ),
  ];

  final List<String> _log = [
    'PA System — checked out by J. Doe · 2h ago',
    'Projector Screen — returned by S. Smith · 5h ago',
  ];

  void _issue(_InventoryItem item) {
    if (item.qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} is out of stock.')),
      );
      return;
    }
    setState(() {
      item.qty -= 1;
      _log.insert(0, '${item.name} — issued · just now');
    });
  }

  void _restock(_InventoryItem item) {
    setState(() {
      item.qty += 5;
      _log.insert(0, '${item.name} — restocked +5 · just now');
    });
  }

  int get _lowStockCount => _items.where((i) => i.isLowStock).length;

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
              if (_lowStockCount > 0) ...[
                _LowStockBanner(count: _lowStockCount),
                const SizedBox(height: 12),
              ],
              const _SearchField(),
              const SizedBox(height: 12),
              const _CategoryChips(),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final item in _items) ...[
                      _InventoryItemCard(
                        item: item,
                        onIssue: () => _issue(item),
                        onRestock: () => _restock(item),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                    const Text('Recent transactions', style: AppText.caption),
                    const SizedBox(height: 8),
                    _RecentTransactionsList(entries: _log),
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
  final int count;
  const _LowStockBanner({required this.count});

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
                  '$count item${count == 1 ? '' : 's'} below minimum threshold',
                  style: const TextStyle(
                    fontFamily: AppText.headerFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.marigoldText,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
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
  final _InventoryItem item;
  final VoidCallback onIssue;
  final VoidCallback onRestock;

  const _InventoryItemCard({
    required this.item,
    required this.onIssue,
    required this.onRestock,
  });

  @override
  Widget build(BuildContext context) {
    final low = item.isLowStock;
    final statusLabel = low ? 'Low Stock' : 'Operational';
    final statusColor = low ? AppColors.brick : AppColors.sageTealText;
    final statusBg = low ? const Color(0xFFFBEAE7) : AppColors.sageTealTint;
    final statusIcon = low ? Icons.warning_amber_rounded : Icons.check_circle_outline;
    final tagColor = low ? AppColors.brick : AppColors.sageTeal;

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
                    child: Icon(item.icon, size: 18, color: AppColors.ink),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
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
              Text(item.name, style: AppText.cardTitle),
              const SizedBox(height: 2),
              Text(item.description, style: AppText.caption),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${item.qty}',
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
                      onPressed: onIssue,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)),
                      child: const Text('Issue Item', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRestock,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)),
                      child: const Text('Restock +5', style: TextStyle(fontSize: 12)),
                    ),
                  ),
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
  final List<String> entries;
  const _RecentTransactionsList({required this.entries});

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
          for (int i = 0; i < entries.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(color: Color(0xFFF4F2EC), shape: BoxShape.circle),
                    child: const Icon(Icons.swap_horiz, size: 14, color: AppColors.ink),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(entries[i], style: AppText.body.copyWith(fontSize: 12)),
                  ),
                ],
              ),
            ),
            if (i != entries.length - 1) const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}