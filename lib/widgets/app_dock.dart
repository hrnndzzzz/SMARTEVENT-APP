import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// How you get around, in whichever shape you like.
///
/// One list of areas, three presentations: a button you can drag where
/// your thumb actually is, a rail down the side, or a bar across the
/// bottom. They are not three navigations — they are three handles on
/// the same one, which is why none of them can show a different set.
class AppDock extends StatelessWidget {
  const AppDock({super.key});

  static void open(BuildContext context, AppArea area) {
    Navigator.of(context).push(MaterialPageRoute(builder: area.builder));
  }

  /// Everything, plus the choice of how to reach it.
  static Future<void> showQuickActions(BuildContext context) {
    return BrutSheet.show<void>(
      context,
      builder: (_) => const _QuickActionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = context.watch<AppSettings>().navStyle;
    return switch (style) {
      NavStyle.floating => const _FloatingDock(),
      NavStyle.rail => const _SideRail(),
      NavStyle.bar => const _BottomBar(),
    };
  }
}

/// The areas worth offering first: whatever is actually waiting, then the
/// rest in their usual order.
List<AppArea> _ranked(AppState app) {
  final areas = areasFor(app.currentRole);
  final waiting = [
    for (final a in areas)
      if ((a.badge?.call(app) ?? 0) > 0) a,
  ];
  final rest = [for (final a in areas) if (!waiting.contains(a)) a];
  return [...waiting, ...rest];
}

// ─────────────────────────── floating ───────────────────────────

class _FloatingDock extends StatefulWidget {
  const _FloatingDock();

  @override
  State<_FloatingDock> createState() => _FloatingDockState();
}

class _FloatingDockState extends State<_FloatingDock> {
  Offset? _drag;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final app = context.watch<AppState>();
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewPaddingOf(context);

    const button = 56.0;
    const margin = AppLayout.gutter;
    final trackW = size.width - button - margin * 2;
    final trackH = size.height - button - margin * 2 - inset.top - inset.bottom;

    final resting = Offset(
      margin + trackW * settings.dockX,
      margin + inset.top + trackH * settings.dockY,
    );
    final at = _drag ?? resting;

    // Expand toward whichever side has room, so the dial never opens off
    // the screen.
    final onRight = settings.dockX >= 0.5;

    return Stack(
      children: [
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _open = false),
              child: ColoredBox(
                color: AppColors.ink.withValues(alpha: 0.45),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: _drag == null && !MediaQuery.disableAnimationsOf(context)
              ? AppMotion.sheet
              : Duration.zero,
          curve: Curves.easeOutCubic,
          left: at.dx,
          top: at.dy,
          child: Column(
            crossAxisAlignment:
                onRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (_open) ...[
                for (final area in _ranked(app).take(4)) ...[
                  _DialItem(
                    area: area,
                    app: app,
                    onRight: onRight,
                    onTap: () {
                      setState(() => _open = false);
                      AppDock.open(context, area);
                    },
                  ),
                  const SizedBox(height: AppLayout.tight),
                ],
                _DialMore(
                  onRight: onRight,
                  onTap: () {
                    setState(() => _open = false);
                    AppDock.showQuickActions(context);
                  },
                ),
                const SizedBox(height: AppLayout.between),
              ],
              GestureDetector(
                onPanStart: (_) => setState(() => _drag = at),
                onPanUpdate: (d) => setState(
                  () => _drag = (_drag ?? at) + d.delta,
                ),
                onPanEnd: (_) {
                  final dropped = _drag ?? at;
                  setState(() => _drag = null);
                  HapticFeedback.selectionClick();
                  // Snap to the nearer side; keep the height it was left at.
                  context.read<AppSettings>().setDockPosition(
                        trackW <= 0 ? 1 : (dropped.dx - margin) / trackW,
                        trackH <= 0
                            ? 0.88
                            : (dropped.dy - margin - inset.top) / trackH,
                      );
                },
                onTap: () => setState(() => _open = !_open),
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _open = false);
                  AppDock.showQuickActions(context);
                },
                child: BrutSurface(
                  fill: Theme.of(context).colorScheme.secondary,
                  radius: AppRadius.pill,
                  shadow: AppShadows.base,
                  width: button,
                  height: button,
                  alignment: Alignment.center,
                  semanticLabel: _open ? 'Close the menu' : 'Open the menu',
                  child: AnimatedRotation(
                    turns: _open ? 0.125 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.accordion,
                    child: const Icon(Icons.apps, size: 26),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialItem extends StatelessWidget {
  const _DialItem({
    required this.area,
    required this.app,
    required this.onRight,
    required this.onTap,
  });

  final AppArea area;
  final AppState app;
  final bool onRight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = area.badge?.call(app) ?? 0;
    final label = BrutSurface(
      fill: context.palette.surface,
      radius: AppRadius.controlAll,
      shadow: AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        count > 0 ? '${area.title} · $count' : area.title,
        style: AppText.buttonLabel.copyWith(fontSize: 12),
      ),
    );
    final dot = BrutSurface(
      onTap: onTap,
      fill: area.tone.fill(context),
      radius: AppRadius.pill,
      shadow: AppShadows.base,
      width: 46,
      height: 46,
      alignment: Alignment.center,
      semanticLabel: area.title,
      child: Icon(area.icon, size: 21),
    );

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: onRight
            ? [label, const SizedBox(width: AppLayout.tight), dot]
            : [dot, const SizedBox(width: AppLayout.tight), label],
      ),
    );
  }
}

class _DialMore extends StatelessWidget {
  const _DialMore({required this.onRight, required this.onTap});

  final bool onRight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            onRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          BrutSurface(
            onTap: onTap,
            fill: context.palette.surface,
            radius: AppRadius.controlAll,
            shadow: AppShadows.sm,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.more_horiz, size: 16),
                const SizedBox(width: 6),
                Text(
                  'All areas',
                  style: AppText.buttonLabel.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── side rail ───────────────────────────

/// A column down the left, with the menu button bulging out of it.
class _SideRail extends StatelessWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final areas = _ranked(app);
    final inset = MediaQuery.viewPaddingOf(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppLayout.tight,
          top: inset.top + AppLayout.tight,
          bottom: inset.bottom + AppLayout.tight,
        ),
        child: BrutSurface(
          fill: context.palette.ink,
          radius: AppRadius.pill,
          shadow: AppShadows.base,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RailButton(
                icon: Icons.apps,
                label: 'All areas',
                fill: Theme.of(context).colorScheme.secondary,
                onTap: () => AppDock.showQuickActions(context),
              ),
              const SizedBox(height: 10),
              for (final area in areas.take(6)) ...[
                _RailButton(
                  icon: area.icon,
                  label: area.title,
                  badge: area.badge?.call(app) ?? 0,
                  onTap: () => AppDock.open(context, area),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fill,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Set only on the menu button, which bulges out of the rail.
  final Color? fill;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final onRail = context.foregroundOn(context.palette.ink);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            label: label,
            button: true,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: fill == null
                  ? null
                  : BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.palette.ink, width: 2),
                    ),
              child: Icon(
                icon,
                size: 20,
                color: fill == null ? onRail : AppColors.ink,
              ),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.coral,
                shape: BoxShape.circle,
                border: Border.all(color: context.palette.ink, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────── bottom bar ───────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final areas = _ranked(app).take(4).toList();
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppLayout.tight,
          AppLayout.tight,
          AppLayout.tight,
          inset > AppLayout.tight ? inset : AppLayout.tight,
        ),
        decoration: BoxDecoration(
          color: context.palette.canvas,
          border: context.borderTop,
        ),
        child: Row(
          children: [
            for (final area in areas)
              Expanded(
                child: _BarButton(
                  icon: area.icon,
                  label: area.title,
                  badge: area.badge?.call(app) ?? 0,
                  onTap: () => AppDock.open(context, area),
                ),
              ),
            Expanded(
              child: _BarButton(
                icon: Icons.apps,
                label: 'All',
                onTap: () => AppDock.showQuickActions(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: label,
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20),
                  if (badge > 0)
                    Positioned(
                      right: -4,
                      top: -3,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.coral,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.palette.canvas,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.navLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── the sheet ───────────────────────────

class _QuickActionsSheet extends StatelessWidget {
  const _QuickActionsSheet();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final settings = context.watch<AppSettings>();
    final areas = areasFor(app.currentRole);

    return BrutSheet(
      title: 'Quick actions',
      subtitle: 'Every area, and where you want the menu to live.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final area in areas) ...[
            BrutListRow(
              title: area.title,
              meta: area.blurb,
              marker: BrutIconTile(
                icon: area.icon,
                tone: area.tone,
                size: 34,
              ),
              trailing: (area.badge?.call(app) ?? 0) > 0
                  ? BrutBadge(
                      label: '${area.badge!(app)}',
                      tone: area.tone,
                      mono: true,
                    )
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                AppDock.open(context, area);
              },
            ),
            const SizedBox(height: AppLayout.tight),
          ],
          const SizedBox(height: AppLayout.between),
          const BrutSectionTitle('Where the menu lives'),
          const SizedBox(height: AppLayout.tight),
          for (final style in NavStyle.values) ...[
            BrutCard(
              radius: AppRadius.rowAll,
              padding: const EdgeInsets.all(12),
              shadow: settings.navStyle == style
                  ? AppShadows.base
                  : AppShadows.sm,
              tone: settings.navStyle == style
                  ? BrutTone.brand
                  : BrutTone.neutral,
              onTap: () => settings.setNavStyle(style),
              child: Row(
                children: [
                  Icon(style.icon, size: 20),
                  const SizedBox(width: AppLayout.between),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          style.label,
                          style: AppText.body
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(style.blurb, style: AppText.caption),
                      ],
                    ),
                  ),
                  if (settings.navStyle == style) ...[
                    const SizedBox(width: AppLayout.tight),
                    const Icon(Icons.check, size: 18),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppLayout.tight),
          ],
        ],
      ),
    );
  }
}
