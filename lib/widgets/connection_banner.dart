import 'dart:async';

import 'package:flutter/material.dart';
import '../state/reachability.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// What the app has to say about the connection, right now.
///
/// Held apart from whoever draws it, because two things can: the brand
/// pill in the header, which is where it belongs on a screen that has
/// one, and the floating pill below, for the screens that do not —
/// Welcome and Sign in, which are exactly where a cold server is waited
/// on.
///
/// Whoever draws it [claim]s it, so the two never say the same thing at
/// once.
class ConnectionNews extends ChangeNotifier {
  String? _message;
  bool _offline = false;
  int _claims = 0;

  String? get message => _message;

  /// Which way it went: the colour follows from this, not from the words.
  bool get offline => _offline;

  /// True while something on screen has undertaken to show it.
  bool get claimed => _claims > 0;

  void claim() => _claims++;
  void release() => _claims = _claims > 0 ? _claims - 1 : 0;

  void say(String message, {required bool offline}) {
    _message = message;
    _offline = offline;
    notifyListeners();
  }

  void clear() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  /// Null where nothing is watching the backend — a widget test
  /// rendering one screen, mostly. The pill then draws itself plain.
  static ConnectionNews? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ConnectionNewsScope>()
      ?.notifier;
}

class _ConnectionNewsScope extends InheritedNotifier<ConnectionNews> {
  const _ConnectionNewsScope({
    required ConnectionNews super.notifier,
    required super.child,
  });
}

/// A short word when the connection changes, and then it goes away.
///
/// It says the state and nothing else. It appears on a *change*, holds
/// for a few seconds, and can be pushed aside with a finger — because
/// the thing you want when the server drops is to be told once, not to
/// have a bar sitting on your screen for as long as the problem lasts.
///
/// The persistent signal is the dot on the avatar. That is always there
/// to be checked; this is only the interruption.
///
/// On a screen with a header the interruption is the brand pill itself,
/// which extends and changes colour for a few seconds. This wrapper
/// still decides *when* there is news; it only draws it where no pill
/// has claimed it.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  static const _hold = Duration(seconds: 3);

  final ConnectionNews _news = ConnectionNews();

  Reachable? _lastSeen;
  Timer? _timer;
  double _slide = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _news.dispose();
    super.dispose();
  }

  /// Out of the build that noticed it.
  ///
  /// The state is read while building, and saying it from there would
  /// be marking the tree dirty in the middle of laying it out. One
  /// frame later costs nothing on a three-second message.
  void _announce(String message, {required bool offline}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer?.cancel();
      _slide = 0;
      _news.say(message, offline: offline);
      _timer = Timer(_hold, () {
        if (mounted) _news.clear();
      });
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _news.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.reachable ?? Reachable.unknown;

    if (state != _lastSeen) {
      final previous = _lastSeen;
      _lastSeen = state;
      // Nothing on the first build: the app opening online is not news.
      if (previous != null) {
        if (state == Reachable.offline &&
            // Not every arrival at offline is news. While it is down
            // the probe goes offline → reconnecting → offline every
            // thirty seconds, and each return counted as the server
            // dropping again — so the one message this is supposed to
            // be became a bar that came back twice a minute for as
            // long as the problem lasted.
            previous != Reachable.reconnecting) {
          _announce('No connection', offline: true);
        } else if (state == Reachable.online &&
            // Back from somewhere, not arriving for the first time.
            //
            // The rule used to be "anything that is not online", and
            // unknown is not online — so the very first answer from the
            // server, which is what every launch begins with, was
            // announced as a recovery. In the demo, which talks to no
            // server at all, the wake probe still reached it and the
            // walkthrough opened under a green "Back online".
            (previous == Reachable.offline ||
                previous == Reachable.reconnecting)) {
          _announce('Back online', offline: false);
        }
      }
    }

    return _ConnectionNewsScope(
      notifier: _news,
      child: AnimatedBuilder(
        animation: _news,
        // Passed through rather than rebuilt: the whole app is under
        // here, and it has no interest in the connection changing.
        child: widget.child,
        builder: (context, child) {
          final message = _news.message;

          return Stack(
            children: [
              child!,
              // Only where no brand pill has undertaken to say it.
              if (message != null && !_news.claimed)
                Positioned(
                  top: MediaQuery.viewPaddingOf(context).top + 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      // Swipe it aside. Either direction, because a
                      // dismissal gesture that only works one way is a
                      // gesture people learn once and then get wrong.
                      onHorizontalDragUpdate: (d) =>
                          setState(() => _slide += d.delta.dx),
                      onHorizontalDragEnd: (_) {
                        if (_slide.abs() > 60) {
                          _dismiss();
                        } else {
                          setState(() => _slide = 0);
                        }
                      },
                      onTap: _dismiss,
                      child: Transform.translate(
                        offset: Offset(_slide, 0),
                        child: Opacity(
                          opacity: (1 - (_slide.abs() / 160))
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          child: _Pill(
                            message: message,
                            offline: _news.offline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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

    // Nothing is watching the backend — in a widget test, say — or
    // nothing has been asked of it yet, so there is no state to report.
    if (state == null || state == Reachable.unknown) {
      return const SizedBox.shrink();
    }

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
      // Returned above; listed so a new state has to be thought about.
      Reachable.unknown => AppColors.leaf,
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
