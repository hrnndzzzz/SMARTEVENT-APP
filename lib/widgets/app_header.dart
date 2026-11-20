import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../state/notice_shelf.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'account_menu.dart';
import 'user_avatar.dart';
import 'brand_pill.dart';
import 'connection_banner.dart';
import 'notice_kind.dart';
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

  const AppHeader({super.key, this.subtitle, this.onAvatarTap, this.onBack});

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

    return Row(
      // spaceBetween rather than a Spacer. A Spacer is an Expanded
      // with flex 1, so it and the Flexible wordmark split the free
      // space evenly and the wordmark came out as "Smar…" on a 411dp
      // phone that had room for all of it. With no Spacer the
      // wordmark is the only flexible child, takes its natural width,
      // and the leftover becomes the gap that pushes the bell and the
      // avatar right.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
        // nothing — and it is where the connection reports itself.
        // Flexible so that on a genuinely narrow phone it shortens
        // rather than striping the header. It should not have to:
        // with the free space no longer split, there is room for the
        // whole wordmark beside an extended notice pill at 411dp.
        const Flexible(child: BrandPill()),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BellWithBadge(),
            const SizedBox(width: 8),
            _Avatar(
              name: app.currentAccount?.name ?? 'Guest',
              onTap: onAvatarTap ?? () => AccountMenu.show(context),
            ),
          ],
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

  /// The newest unread notice the pill has already shown. Kept so a
  /// rebuild for some unrelated reason does not announce the same
  /// arrival again.
  String? _announced;

  /// What the pill is saying right now, or null when it is just a
  /// bell. Set when a notice arrives, cleared a few seconds later.
  NoticeBadge? _saying;
  Timer? _hold;

  /// The same few seconds the wordmark gives the connection, so being
  /// told something by the header reads as one behaviour wherever it
  /// happens.
  static const Duration _holdFor = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // build() watches AppState, so this runs whenever it notifies.
    // Reading here rather than watching: watch belongs in build.
    final app = context.read<AppState>();
    final newest = app.notices.where((n) => n.isUnread).firstOrNull;

    if (newest == null) {
      _announced = null;
      return;
    }
    if (newest.id == _announced) return;
    _announced = newest.id;
    _say(noticeBadge(newest.kind));
  }

  /// Extends the pill, holds, and lets it shrink back.
  void _say(NoticeBadge badge) {
    _hold?.cancel();
    // Not inside the build that discovered it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _saying = badge);
      _hold = Timer(_holdFor, () {
        if (mounted) setState(() => _saying = null);
      });
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
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
    final app = context.watch<AppState>();
    // The badge must equal the number of rows the panel will show, or
    // the window it opens contradicts it. The panel hides notices this
    // phone has swiped away, so the badge has to discount them too —
    // before this, swiping an unread one away left the badge counting
    // a row that was no longer there.
    //
    // Until the inbox has been fetched there is nothing to discount
    // against, so the server's own count stands.
    NoticeShelf? shelf;
    try {
      shelf = context.watch<NoticeShelf>();
    } on ProviderNotFoundException {
      shelf = null;
    }
    final count = (app.notices.isEmpty || shelf == null)
        ? app.unreadNoticeCount
        : app.notices
              .where((n) => n.isUnread && !shelf!.isDismissed(n.id))
              .length;
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
    // The wordmark beside this one goes coloured when the connection
    // changes. Two tinted pills in one header read as two status
    // indicators disagreeing with each other, so only one of them
    // speaks at a time and the connection wins: it is the more urgent
    // of the two, and a notice keeps until the inbox is opened.
    final connectionSpeaking = ConnectionNews.maybeOf(context)?.message != null;
    final saying = (still || connectionSpeaking) ? null : _saying;

    final bell = _NoticePill(
      count: count,
      saying: saying,
      flush: 0,
      angle: 0,
      onPressed: () => NotificationMenu.show(context),
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
              return _NoticePill(
                angle: angle,
                // The box does not flush red while it is already
                // wearing the notice's own colour: two colours
                // fighting over one pill says nothing.
                flush: saying == null ? envelope : 0,
                count: count,
                saying: saying,
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
    // The tone rather than the raw hex, so the badge is held down with
    // everything else on the navy — and the number measured against the
    // fill rather than taking the page's ink, which on a dark canvas is
    // light and was being printed on a light red.
    final resting = BrutTone.coral.fill(context);
    final fill = Color.lerp(resting, AppColors.alert, swell) ?? resting;

    return Transform.scale(
      scale: 1 + swell * 0.28,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        constraints: const BoxConstraints(minWidth: 18),
        decoration: BoxDecoration(
          color: fill,
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
            color: context.foregroundOn(fill),
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// The bell, and the word when there is something to say.
///
/// A pill rather than a square, so the three things in the header —
/// the wordmark, this, the avatar — share one shape language. It is a
/// bell on its own, and when a notice arrives it extends to the right
/// to make room for one word naming what the notice is about, takes
/// that notice's colour, and shrinks back a few seconds later.
///
/// Deliberately the same behaviour as the wordmark reporting the
/// connection: nothing new appears over the header, nothing is
/// covered, and the thing that was already there grows to tell you.
class _NoticePill extends StatelessWidget {
  const _NoticePill({
    required this.count,
    required this.saying,
    required this.angle,
    required this.flush,
    required this.onPressed,
  });

  final int count;

  /// The word and the colour, or null when the pill is just a bell.
  final NoticeBadge? saying;

  /// Radians to turn the bell by, this frame.
  final double angle;

  /// 0 to 1 across the attention swell, for how red the box is.
  final double flush;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final resting = BrutTone.neutral.fill(context);
    final badge = saying;
    final target = badge == null
        ? Color.lerp(resting, BrutTone.coral.fill(context), flush * 0.85) ??
              resting
        : badge.tone.fill(context);

    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : BrandPill.motion;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, colour, _) {
        final fill = colour ?? target;
        // Measured against the colour the pill is on this frame, not
        // the one it is heading for: mid-fade it is neither.
        final ink = context.foregroundOn(fill);

        return BrutSurface(
          onTap: onPressed,
          semanticLabel: switch ((count, badge)) {
            (0, _) => 'Notifications',
            (_, final b?) => 'Notifications, $count unread, newest: ${b.label}',
            _ => 'Notifications, $count unread',
          },
          fill: fill,
          radius: AppRadius.pill,
          shadow: AppShadows.sm,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            // Grows to the right, away from the avatar it sits beside,
            // so the bell itself never moves.
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: angle,
                  child: Icon(Icons.notifications_none, size: 17, color: ink),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  // Flexible so a narrow phone shortens the word
                  // rather than striping the header.
                  Flexible(
                    child: Text(
                      badge.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.monoLabel.copyWith(
                        fontSize: 11,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
