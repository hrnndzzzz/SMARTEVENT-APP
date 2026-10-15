import 'dart:async';

import 'package:flutter/material.dart';
import '../state/reachability.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// A short word when the connection changes, and then it goes away.
///
/// It says the state and nothing else. It appears on a *change*, holds
/// for a few seconds, and can be pushed aside with a finger — because
/// the thing you want when the server drops is to be told once, not to
/// have a bar sitting on your screen for as long as the problem lasts.
///
/// The persistent signal is the dot on the avatar. That is always there
/// to be checked; this is only the interruption.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  static const _hold = Duration(seconds: 3);

  Reachable? _lastSeen;
  String? _message;
  bool _offline = false;
  Timer? _timer;
  double _slide = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show(String message, {required bool offline}) {
    _timer?.cancel();
    setState(() {
      _message = message;
      _offline = offline;
      _slide = 0;
    });
    _timer = Timer(_hold, () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.reachable ?? Reachable.online;

    if (state != _lastSeen) {
      final previous = _lastSeen;
      _lastSeen = state;
      // Nothing on the first build: the app opening online is not news.
      if (previous != null) {
        if (state == Reachable.offline) {
          _show('No connection to the server', offline: true);
        } else if (state == Reachable.online && previous != Reachable.online) {
          _show('Back online', offline: false);
        }
      }
    }

    final message = _message;

    return Stack(
      children: [
        widget.child,
        if (message != null)
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 6,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                // Swipe it aside. Either direction, because a dismissal
                // gesture that only works one way is a gesture people
                // learn once and then get wrong.
                onHorizontalDragUpdate: (d) =>
                    setState(() => _slide += d.delta.dx),
                onHorizontalDragEnd: (_) {
                  if (_slide.abs() > 60) {
                    _timer?.cancel();
                    setState(() => _message = null);
                  } else {
                    setState(() => _slide = 0);
                  }
                },
                onTap: () {
                  _timer?.cancel();
                  setState(() => _message = null);
                },
                child: Transform.translate(
                  offset: Offset(_slide, 0),
                  child: Opacity(
                    opacity: (1 - (_slide.abs() / 160))
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    child: _Pill(message: message, offline: _offline),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.message, required this.offline});

  final String message;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      fill: offline ? AppColors.coral : AppColors.mint,
      radius: AppRadius.pill,
      shadow: AppShadows.base,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(message, style: AppText.buttonLabel.copyWith(fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// The dot that sits on the avatar: green answering, coral not, and
/// blinking while a retry is in flight.
class ConnectionDot extends StatefulWidget {
  const ConnectionDot({super.key, this.size = 14, this.ringColor});

  final double size;

  /// The ring that lifts the dot off whatever is behind it. Null for a
  /// dot that is already inside a bordered pill.
  final Color? ringColor;

  @override
  State<ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.reachable;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Nothing is watching the backend — in a widget test, say — so there
    // is no state to report.
    if (state == null) return const SizedBox.shrink();

    if (state == Reachable.reconnecting && !reduceMotion) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
    } else if (_blink.isAnimating) {
      _blink.stop();
      _blink.value = 1;
    }

    final color = switch (state) {
      Reachable.online => AppColors.leaf,
      Reachable.offline => AppColors.coral,
      Reachable.reconnecting => AppColors.sun,
    };

    return FadeTransition(
      opacity: state == Reachable.reconnecting && !reduceMotion
          ? Tween<double>(begin: 0.35, end: 1).animate(_blink)
          : const AlwaysStoppedAnimation(1),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.ringColor ?? context.palette.ink,
            width: widget.ringColor == null ? 1.5 : 2.5,
          ),
        ),
      ),
    );
  }
}
