import 'package:flutter/material.dart';
import '../state/reachability.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// A pill that drops in when the backend stops answering, and again when
/// it comes back.
///
/// It appears on a *change*, not on a state, so a working app never
/// carries a permanent banner. Going offline it stays until the backend
/// returns, because that is a condition you need to keep knowing about;
/// coming back it says so for a few seconds and leaves.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  Reachable? _lastSeen;
  bool _showRecovered = false;

  @override
  Widget build(BuildContext context) {
    final state = context.reachable ?? Reachable.online;

    if (state != _lastSeen) {
      final cameBack =
          _lastSeen != null &&
          _lastSeen != Reachable.online &&
          state == Reachable.online;
      _lastSeen = state;
      if (cameBack) {
        _showRecovered = true;
        Future.delayed(const Duration(milliseconds: 2600), () {
          if (mounted) setState(() => _showRecovered = false);
        });
      }
    }

    final offline = state != Reachable.online;
    final visible = offline || _showRecovered;

    return Stack(
      children: [
        widget.child,
        if (visible)
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 6,
            left: 0,
            right: 0,
            child: Center(
              child: _Pill(
                reconnecting: state == Reachable.reconnecting,
                offline: offline,
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.reconnecting, required this.offline});

  final bool reconnecting;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final label = !offline
        ? 'Back online'
        : reconnecting
        ? 'Reconnecting'
        : 'No connection to the server';
    final detail = !offline
        ? 'The server is answering again'
        : 'Changes will not save until it answers';

    return BrutSurface(
      fill: offline ? AppColors.coral : AppColors.mint,
      radius: AppRadius.pill,
      shadow: AppShadows.base,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConnectionDot(size: 10, ringColor: null),
          const SizedBox(width: 8),
          Text(label, style: AppText.buttonLabel.copyWith(fontSize: 12.5)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              detail,
              style: AppText.caption.copyWith(color: AppColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
