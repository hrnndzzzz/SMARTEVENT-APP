import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'account_menu.dart';
import 'user_avatar.dart';
import 'connection_banner.dart';
import 'colour_pulse.dart';
import 'notification_menu.dart';

/// The top bar on every section screen: the brand pill, who you are signed
/// in as, the bell, and the avatar.
///
/// The department accent is used as a *fill* here, never as text. The
/// palette is light enough for ink on top of it and far too light to read
/// against the canvas, which is why the wordmark lives inside a pill
/// rather than being coloured directly.
class AppHeader extends StatelessWidget {
  /// Kept for callers that still pass it; the header no longer draws it.
  /// The dashboard says who you are under the greeting, where there is
  /// room for it, and the account menu says it in full.
  final String? subtitle;

  /// Overrides what the avatar does. It opens the account menu by
  /// default, which is what every screen wanted.
  final VoidCallback? onAvatarTap;

  /// Shown when this screen was pushed rather than swiped to. Screens
  /// that used to be tabs did not need one; the same screens opened from
  /// the menu very much do.
  final VoidCallback? onBack;

  const AppHeader({
    super.key,
    this.subtitle,
    this.onAvatarTap,
    this.onBack,
  });

  /// `CITE · TREASURER`. Falls back to whichever half is known rather than
  /// printing a placeholder for the other.
  static String? scopeLineFor(AppState app) {
    final role = app.currentRole?.label;
    final parts = [app.departmentLabel, role].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // The department accent comes from the theme rather than from state:
    // main.dart puts it there, so every identity surface reads one value.
    final accent = Theme.of(context).colorScheme.secondary;

    return Row(
      children: [
        if (onBack != null) ...[
          BrutIconButton(
            icon: Icons.arrow_back,
            label: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
        ],
        // One row, three things, all on the same baseline. The role used
        // to sit under the wordmark, which pushed the pill half a line
        // above the two buttons it is supposed to line up with.
        // The wordmark goes home. On the dashboard, where home already
        // is, it does the one thing it can usefully do instead of
        // nothing.
        BrutSurface(
          fill: accent,
          radius: AppRadius.pill,
          shadow: AppShadows.sm,
          padding: const EdgeInsets.fromLTRB(10, 5, 14, 5),
          // Whether it has somewhere to go is a question the navigator
          // can already answer: anywhere with a route under it is a
          // screen you arrived at, and the way out is home.
          semanticLabel: Navigator.of(context).canPop()
              ? 'Back to the dashboard'
              : 'SmartEvent',
          onTap: () => Navigator.of(context).canPop()
              ? Navigator.of(context).popUntil((route) => route.isFirst)
              : ColourPulse.show(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 15, color: AppColors.ink),
              const SizedBox(width: 5),
              Text('SmartEvent', style: AppText.wordmark),
            ],
          ),
        ),
        const Spacer(),
        const _BellWithBadge(),
        const SizedBox(width: 8),
        _Avatar(
          name: app.currentAccount?.name ?? 'Guest',
          onTap: onAvatarTap ?? () => AccountMenu.show(context),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            label: 'Account',
            button: true,
            child: UserAvatar(name: name, size: 38),
          ),
        ),
        // Whether the backend is answering, where you are already looking.
        Positioned(
          right: -2,
          bottom: -2,
          child: ConnectionDot(ringColor: context.palette.canvas),
        ),
      ],
    );
  }
}

/// The bell, with an unread count when there is one.
///
/// The number comes from `/notifications/unread-count` via AppState rather
/// than from counting a loaded list, so it is right even before the inbox
/// has been opened. No badge at all when the count is zero — a "0" is
/// noise.
///
/// When something is unread the bell asks for attention on a cycle: it
/// fades to the number, shakes, and fades back. Once every eight seconds
/// rather than continuously, because a thing that moves forever stops
/// being noticed and starts being irritating.
class _BellWithBadge extends StatefulWidget {
  const _BellWithBadge();

  @override
  State<_BellWithBadge> createState() => _BellWithBadgeState();
}

class _BellWithBadgeState extends State<_BellWithBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// How far through one swell we are, 0 to 1, and 0 for most of the
  /// cycle. The bell is still for about six of the eight seconds.
  static double _phase(double t) {
    const share = 0.26;
    return t < share ? t / share : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final count = context.watch<AppState>().unreadNoticeCount;
    // Reduce-motion is a preference, not a requirement: a host without
    // the settings provider — a widget test, mostly — should still get a
    // working bell rather than an exception.
    var reduceMotion = false;
    try {
      reduceMotion = context.watch<AppSettings>().reduceMotion;
    } on ProviderNotFoundException {
      reduceMotion = false;
    }
    final still = MediaQuery.disableAnimationsOf(context) || reduceMotion;

    // One handler, on the button itself. The previous arrangement had a
    // gesture wrapper outside and an onPressed inside, and the inner one
    // won every tap — which is why this still opened a screen after it
    // was supposed to open a window.
    final bell = BrutIconButton(
      icon: Icons.notifications_none,
      label: count > 0 ? 'Notifications, $count unread' : 'Notifications',
      onPressed: () => NotificationMenu.show(context),
      size: 38,
    );

    if (count == 0) return bell;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (still)
          bell
        else
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final p = _phase(_controller.value);
              // Three shakes across the swell, fading in and out at the
              // ends so it never starts or stops with a jolt.
              final envelope = p == 0 ? 0.0 : math.sin(p * math.pi);
              final angle = math.sin(p * math.pi * 6) * 0.14 * envelope;

              // The bell rings; the box it sits in does not. Rotating the
              // whole button turned the square, which read as the
              // interface wobbling rather than something arriving. The
              // box pulses red once instead, on the same swell.
              return _RingingBell(
                angle: angle,
                flush: envelope,
                count: count,
                onPressed: () => NotificationMenu.show(context),
              );
            },
          ),
        Positioned(
          right: -5,
          top: -5,
          child: still
              ? _Badge(count: count, swell: 0)
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final p = _phase(_controller.value);
                    return _Badge(
                      count: count,
                      swell: p == 0 ? 0 : math.sin(p * math.pi),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The count. [swell] runs 0 to 1 and back across one attention cycle,
/// growing the badge and deepening its red at the peak.
class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.swell});

  final int count;
  final double swell;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1 + swell * 0.28,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        constraints: const BoxConstraints(minWidth: 18),
        decoration: BoxDecoration(
          color: Color.lerp(AppColors.coral, AppColors.alert, swell),
          borderRadius: AppRadius.pill,
          border: context.borderAll,
        ),
        child: Text(
          // Past 99 the exact number stops being useful and starts
          // breaking the layout.
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: AppText.monoLabel.copyWith(
            fontSize: 9,
            color: context.palette.ink,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// The bell mid-ring: the icon turns, the box flushes red, the square
/// stays square.
class _RingingBell extends StatelessWidget {
  const _RingingBell({
    required this.angle,
    required this.flush,
    required this.count,
    required this.onPressed,
  });

  /// Radians to turn the bell by, this frame.
  final double angle;

  /// 0 to 1 across the swell, for how red the box is.
  final double flush;

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resting = BrutTone.neutral.fill(context);

    return BrutSurface(
      onTap: onPressed,
      semanticLabel: 'Notifications, $count unread',
      fill: Color.lerp(resting, AppColors.coral, flush * 0.85) ?? resting,
      radius: AppRadius.controlAll,
      shadow: AppShadows.sm,
      width: 38,
      height: 38,
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: angle,
        child: Icon(
          Icons.notifications_none,
          size: 38 * 0.45,
          color: palette.ink,
        ),
      ),
    );
  }
}
