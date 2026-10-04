import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';

class CircleMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  CircleMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class CircleMenu extends StatefulWidget {
  final List<CircleMenuItem> items;
  final Color color;

  const CircleMenu({super.key, required this.items, required this.color});

  @override
  State<CircleMenu> createState() => _CircleMenuState();
}

class _CircleMenuState extends State<CircleMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isOpen = false;
  bool _isPressed = false;

  // Adjust this single value to move the whole menu stack up or down
  static const double baseBottomOffset = 24;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const double mainButtonSize = 56;
    const double smallButtonSize = 48;
    const double itemSpacing = 64;
    // Light enough to keep ink on top legible, dark enough to read as
    // the area's accent.
    final tint = Color.lerp(widget.color, context.palette.surface, 0.55)!;

    return Stack(
      children: [
        IgnorePointer(
          ignoring: !_isOpen,
          child: AnimatedOpacity(
            opacity: _isOpen ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: GestureDetector(
              onTap: _toggle,
              // The scrim is flat ink at half strength, like the sheets.
              child: ColoredBox(
                color: context.palette.ink.withValues(alpha: 0.5),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),

        // Stacked vertical items, each with its own staggered delay
        ...List.generate(widget.items.length, (index) {
          const double gapFromMain = 16;
          final itemBottom =
              baseBottomOffset +
              mainButtonSize +
              gapFromMain +
              (itemSpacing * index);

          final start = (index / widget.items.length) * 0.5;
          final end = start + 0.5;
          final animation = CurvedAnimation(
            parent: _controller,
            curve: Interval(start, end, curve: Curves.easeOutBack),
          );

          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final progress = animation.value.clamp(0.0, 1.0);
              return Positioned(
                bottom: itemBottom,
                right: 24 + (mainButtonSize - smallButtonSize) / 2,
                child: Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, (1 - progress) * 20),
                    child: IgnorePointer(
                      ignoring: !_isOpen,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BrutSurface(
                            fill: context.palette.surface,
                            radius: AppRadius.controlAll,
                            shadow: AppShadows.sm,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Text(
                              widget.items[index].label,
                              style: AppText.buttonLabel.copyWith(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          BrutSurface(
                            onTap: () {
                              widget.items[index].onTap();
                              _toggle();
                            },
                            semanticLabel: widget.items[index].label,
                            fill: tint,
                            radius: AppRadius.pill,
                            shadow: AppShadows.base,
                            width: smallButtonSize,
                            height: smallButtonSize,
                            alignment: Alignment.center,
                            child: Icon(
                              widget.items[index].icon,
                              color: context.palette.ink,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),

        // Main trigger button
        Positioned(
          bottom: baseBottomOffset,
          right: 24,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: _toggle,
            child: AnimatedContainer(
              duration: AppMotion.press,
              curve: Curves.easeOut,
              width: mainButtonSize,
              height: mainButtonSize,
              alignment: Alignment.center,
              // Same press as every other control: it drops onto its own
              // shadow rather than scaling.
              transform: _isPressed
                  ? Matrix4.translationValues(3, 3, 0)
                  : Matrix4.identity(),
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: context.borderAll,
                boxShadow: _isPressed
                    ? AppShadows.none
                    : context.shadows(AppShadows.base),
              ),
              child: AnimatedRotation(
                turns: _isOpen ? 0.125 : 0,
                duration: AppMotion.accordion,
                child: Icon(Icons.apps, color: context.palette.ink, size: 28),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
