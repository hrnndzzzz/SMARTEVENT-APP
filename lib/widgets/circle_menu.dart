import 'package:flutter/material.dart';

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
    final tint = Color.lerp(widget.color, Colors.white, 0.92)!;

    return Stack(
      children: [
        IgnorePointer(
          ignoring: !_isOpen,
          child: AnimatedOpacity(
            opacity: _isOpen ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: GestureDetector(
              onTap: _toggle,
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          ),
        ),

        // Stacked vertical items, each with its own staggered delay

        ...List.generate(widget.items.length, (index) {
          const double gapFromMain = 16;
          final itemBottom =
              baseBottomOffset + mainButtonSize + gapFromMain + (itemSpacing * index);

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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.items[index].label,
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              widget.items[index].onTap();
                              _toggle();
                            },
                            child: Container(
                              width: smallButtonSize,
                              height: smallButtonSize,
                              decoration: BoxDecoration(
                                color: tint,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: widget.color.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.items[index].icon,
                                color: widget.color,
                                size: 22,
                              ),
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
            child: AnimatedScale(
              scale: _isPressed ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: mainButtonSize,
                height: mainButtonSize,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedRotation(
                  turns: _isOpen ? 0.125 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(Icons.apps, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}