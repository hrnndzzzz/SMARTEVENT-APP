import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Washes the screen in a colour, once, and gets out of the way.
///
/// The wordmark had nothing to do on the dashboard — you are already
/// there. Rather than make it dead, it does this.
///
/// Honours the reduce-motion setting: somebody who has asked the system
/// to stop things moving has not asked for a flashing screen.
abstract final class ColourPulse {
  static final _random = Random();

  /// The accents it picks from. Blue and green lead, as asked for;
  /// the rest keep it from being the same joke twice.
  static const List<Color> palette = [
    AppColors.brand,
    AppColors.mint,
    AppColors.violet,
    AppColors.sun,
    AppColors.coral,
  ];

  /// A colour that is not [avoiding], so two taps never look like one.
  static Color pick({Color? avoiding}) {
    final options = [
      for (final c in palette)
        if (c != avoiding) c,
    ];
    return options[_random.nextInt(options.length)];
  }

  /// Returns whether it actually ran, which is false when motion is
  /// turned down or there is no overlay to put it in.
  static bool show(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return false;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return false;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Pulse(onDone: entry.remove),
    );
    overlay.insert(entry);
    return true;
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Color _colour = ColourPulse.pick();
  late final Color _second = ColourPulse.pick(avoiding: _colour);

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing here should ever take a tap: it is a flourish over a
    // working screen, not a layer on top of it.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // Up and back down, so it swells rather than snapping on.
          final strength = sin(t * pi) * 0.5;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _colour.withValues(alpha: strength),
                  _second.withValues(alpha: strength * 0.7),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}
