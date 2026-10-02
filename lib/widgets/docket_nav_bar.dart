import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Shared bottom nav bar for SmartEvent's six sections.
/// Pass the index of whichever tab should show as active.
///
/// The active tab is an accent-filled block with ink on it, not coloured
/// text: the department accents are fills, and tinted text on the canvas
/// would fail contrast at this size.
class DocketNavBar extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int>? onTap;

  const DocketNavBar({super.key, required this.activeIndex, this.onTap});

  static const _items = [
    (Icons.grid_view_outlined, 'Home'),
    (Icons.search, 'Search'),
    (Icons.document_scanner_outlined, 'Scan'),
    (Icons.warning_amber_outlined, 'Risk'),
    (Icons.inventory_2_outlined, 'Stock'),
    (Icons.event_outlined, 'Events'),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppState>().themeColor;
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, inset > 8 ? inset : 8),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: AppBorders.top,
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final isActive = i == activeIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: BrutSurface(
                onTap: onTap == null ? null : () => onTap!(i),
                semanticLabel: _items[i].$2,
                fill: isActive ? accent : AppColors.canvas,
                radius: AppRadius.controlAll,
                shadow: isActive ? AppShadows.sm : AppShadows.none,
                side: isActive
                    ? AppBorders.side
                    : const BorderSide(color: Colors.transparent, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _items[i].$1,
                      size: 18,
                      color: isActive ? AppColors.ink : AppColors.subtle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _items[i].$2.toUpperCase(),
                      style: AppText.navLabel.copyWith(
                        color: isActive ? AppColors.ink : AppColors.subtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
