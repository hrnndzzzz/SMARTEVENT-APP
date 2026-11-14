import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/module_identity.dart';
import '../theme/palette.dart';

/// The block at the top of a module that says which module it is.
///
/// The reviewer's complaint was that you had to read the title to know
/// where you were: sixteen screens share one top bar, so Money,
/// Inventory, Reports and Flagged were the same screen with a different
/// word on it. This replaces that word with something you can
/// recognise without reading — a full-width block in the module's own
/// colour, carrying its icon.
///
/// It takes the place of the plain `Text(title)` each screen used to
/// draw, rather than sitting above it, so nothing is said twice.
class ModuleBand extends StatelessWidget {
  const ModuleBand({
    super.key,
    required this.module,
    this.title,
    this.icon,
    this.subtitle,
    this.trailing,
  });

  /// Which part of the app this is. Carries the colour, and the title
  /// and icon unless the screen overrides them.
  final Module module;

  /// For a screen inside a module rather than the module's own front
  /// page — Receipts under Money. It keeps the module's colour, because
  /// the point is that it still feels like the money area.
  final String? title;
  final IconData? icon;

  /// One line under the title. The module's own blurb, when it has one
  /// worth repeating here.
  final String? subtitle;

  /// A control that belongs to the whole module, such as a scope
  /// picker. Sits on the band rather than below it, so the band is the
  /// module's header and not just a label.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fill = module.color;
    final ink = context.foregroundOn(fill);

    return BrutSurface(
      fill: fill,
      radius: AppRadius.cardAll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The icon sits in a punched-out tile rather than loose on
          // the fill, so it reads as part of the block at a glance
          // instead of as a stray glyph beside the words.
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon ?? module.icon, size: 22, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? module.title,
                  style: AppText.display.copyWith(fontSize: 26, color: ink),
                ),
                if (subtitle case final line?) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style: AppText.caption.copyWith(
                      color: ink.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing case final control?) ...[
            const SizedBox(width: AppLayout.tight),
            control,
          ],
        ],
      ),
    );
  }
}
