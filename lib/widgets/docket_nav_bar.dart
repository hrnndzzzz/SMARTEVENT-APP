import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class DocketNavBar extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int>? onTap;

  const DocketNavBar({super.key, required this.activeIndex, this.onTap});

  static const _items = [
    (Icons.grid_view_outlined, 'Dashboard'),
    (Icons.search, 'Search'),
    (Icons.document_scanner_outlined, 'Scanner'),
    (Icons.warning_amber_outlined, 'Risk'),
    (Icons.inventory_2_outlined, 'Inventory'),
    (Icons.event_outlined, 'Events'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (i) {
          final isActive = i == activeIndex;
          final color = isActive ? AppColors.indigo : AppColors.inkFaint;
          return GestureDetector(
            onTap: onTap == null ? null : () => onTap!(i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_items[i].$1, size: 18, color: color),
                const SizedBox(height: 3),
                Text(
                  _items[i].$2,
                  style: AppText.navLabel.copyWith(
                    fontSize: 9,
                    color: color,
                    fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}