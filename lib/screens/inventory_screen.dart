import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    try {
      final data = await SupabaseService.client
          .from('inventory')
          .select()
          .order('created_at', ascending: false);

      debugPrint('Inventory data: $data');

      if (!mounted) return;

      setState(() {
        _items = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Inventory error: $e');

      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // END: Scaffold
      body: SafeArea(
        // END: SafeArea
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Error loading inventory:\n$_error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadInventory,
                    // END: RefreshIndicator
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        8,
                      ),
                      // END: ListView
                      children: [
                        const _InventoryHeader(),
                        const SizedBox(height: 14),

                        _LowStockBanner(
                          items: _items,
                        ),

                        const SizedBox(height: 12),
                        const _SearchField(),
                        const SizedBox(height: 12),
                        const _CategoryChips(),
                        const SizedBox(height: 14),

                        // REAL SUPABASE DATA
                        ..._items.map(
                          (item) {
                            final quantity =
                                (item['quantity'] as num?)?.toInt() ?? 0;

                            final threshold =
                                (item['low_stock_threshold'] as num?)
                                        ?.toInt() ??
                                    0;

                            final isLowStock = quantity <= threshold;

                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: 10,
                              ),
                              child: _InventoryItemCard(
                                icon: Icons.inventory_2_outlined,
                                name: item['item_name']?.toString() ??
                                    'Unnamed Item',
                                description:
                                    item['description']?.toString() ?? '',
                                qty: quantity,
                                statusLabel: isLowStock
                                    ? 'Low Stock'
                                    : 'Operational',
                                statusColor: isLowStock
                                    ? AppColors.brick
                                    : AppColors.sageTealText,
                                statusBg: isLowStock
                                    ? const Color(0xFFFBEAE7)
                                    : AppColors.sageTealTint,
                                statusIcon: isLowStock
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline,
                                tagColor: isLowStock
                                    ? AppColors.brick
                                    : AppColors.sageTeal,
                                showRestock: true,
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'Recent transactions',
                          style: AppText.caption,
                        ),

                        const SizedBox(height: 8),

                        const _RecentTransactionsList(),
                      ],
                    ),
                  ),
      ),
    );
  }
}

// ============================================================
// INVENTORY HEADER
// ============================================================

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'SmartEvent',
              style: AppText.wordmark,
            ),
            Icon(
              Icons.notifications_none,
              color: AppColors.indigo,
              size: 22,
            ),
          ],
        ),

        const SizedBox(height: 10),

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

        const Text(
          'Track and manage campus resources.',
          style: AppText.caption,
        ),
      ],
    );
  }
}

// ============================================================
// LOW STOCK BANNER
// ============================================================

class _LowStockBanner extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _LowStockBanner({
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final lowStockCount = items.where((item) {
      final quantity =
          (item['quantity'] as num?)?.toInt() ?? 0;

      final threshold =
          (item['low_stock_threshold'] as num?)?.toInt() ?? 0;

      return quantity <= threshold;
    }).length;

    if (lowStockCount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.sageTealTint,
          border: Border.all(
            color: AppColors.sageTeal,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.check_circle_outline,
                size: 18,
                color: AppColors.sageTealText,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory levels are okay',
                    style: TextStyle(
                      fontFamily:
                          AppText.headerFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: AppColors.sageTealText,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'No items are currently below the minimum threshold.',
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 11,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.marigoldTint,
        border: Border.all(
          color: const Color(0xFFE3D6B4),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColors.marigoldText,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '$lowStockCount items below minimum threshold',
                  style: TextStyle(
                    fontFamily:
                        AppText.headerFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.marigoldText,
                  ),
                ),

                const SizedBox(height: 2),

                const Text(
                  'Immediate action needed to ensure event continuity.',
                  style: TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SEARCH FIELD
// ============================================================

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: AppColors.border,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.search,
            size: 18,
            color: AppColors.inkMuted,
          ),

          SizedBox(width: 8),

          Text(
            'Search inventory...',
            style: TextStyle(
              color: AppColors.inkFaint,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CATEGORY CHIPS
// ============================================================

class _CategoryChips extends StatelessWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(
            'All Items',
            selected: true,
          ),

          const SizedBox(width: 8),

          _chip('In-Stock'),

          const SizedBox(width: 8),

          _chip('Issued'),
        ],
      ),
    );
  }

  Widget _chip(
    String label, {
    bool selected = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.indigo
            : AppColors.surface,
        border: selected
            ? null
            : Border.all(
                color: AppColors.border,
                width: 0.5,
              ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 12,
          fontWeight: selected
              ? FontWeight.w500
              : FontWeight.w400,
          color: selected
              ? Colors.white
              : AppColors.ink,
        ),
      ),
    );
  }
}

// ============================================================
// INVENTORY ITEM CARD
// ============================================================

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
          padding: const EdgeInsets.fromLTRB(
            12,
            14,
            16,
            14,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
              color: AppColors.border,
              width: 0.5,
            ),
            borderRadius:
                BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFF4F2EC),
                      borderRadius:
                          BorderRadius.circular(9),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: AppColors.ink,
                    ),
                  ),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        Icon(
                          statusIcon,
                          size: 11,
                          color: statusColor,
                        ),

                        const SizedBox(width: 4),

                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontFamily:
                                AppText.bodyFamily,
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                name,
                style: AppText.cardTitle,
              ),

              const SizedBox(height: 2),

              Text(
                description,
                style: AppText.caption,
              ),

              const SizedBox(height: 10),

              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$qty',
                      style: const TextStyle(
                        fontFamily:
                            AppText.monoFamily,
                        fontWeight:
                            FontWeight.w500,
                        fontSize: 20,
                        color: AppColors.ink,
                      ),
                    ),

                    const TextSpan(
                      text: ' Qty available',
                      style: TextStyle(
                        fontFamily:
                            AppText.bodyFamily,
                        fontSize: 12,
                        color:
                            AppColors.inkMuted,
                      ),
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
                      style:
                          ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 9,
                        ),
                      ),
                      child: const Text(
                        'Issue Item',
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                  if (showRestock) ...[
                    const SizedBox(width: 8),

                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        style:
                            OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(
                            vertical: 9,
                          ),
                        ),
                        child: const Text(
                          'Restock',
                          style: TextStyle(
                            fontSize: 12,
                          ),
                        ),
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
              borderRadius:
                  const BorderRadius.horizontal(
                right: Radius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// RECENT TRANSACTIONS
// ============================================================

class _RecentTransactionsList
    extends StatelessWidget {
  const _RecentTransactionsList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: AppColors.border,
          width: 0.5,
        ),
        borderRadius:
            BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _row(
            icon: Icons.arrow_outward,
            iconBg:
                const Color(0xFFF4F2EC),
            iconColor: AppColors.ink,
            text:
                'PA System — checked out by JP. Buffe',
            time: '2h ago',
          ),

          const Divider(
            height: 1,
            color: AppColors.border,
          ),

          _row(
            icon: Icons.reply,
            iconBg:
                AppColors.sageTealTint,
            iconColor:
                AppColors.sageTealText,
            text:
                'Projector Screen — returned by J. Hernandez',
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
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 14,
              color: iconColor,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style:
                      AppText.body.copyWith(
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 1),

                Text(
                  time,
                  style: AppText.moneySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}