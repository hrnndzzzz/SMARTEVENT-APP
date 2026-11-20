import 'dart:async';

import 'package:flutter/material.dart';

import '../state/reachability.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'colour_pulse.dart';
import 'connection_banner.dart';

/// The wordmark at the top of every section screen, and the place the
/// app says whether the server is answering.
///
/// It used to be told in a pill that dropped out of nowhere over the
/// header — a second object, covering the first, for three seconds.
/// Here the header itself reports it: the brand pill extends to make
/// room for the word and takes the colour of what happened, then
/// shrinks back to the department accent. Nothing new appears, and
/// nothing is covered.
///
/// The persistent signal is still the dot on the avatar. This is the
/// interruption; that is the thing you can go and check.
class BrandPill extends StatefulWidget {
  const BrandPill({super.key});

  /// How long the extend and the colour change take, each way. Slow
  /// enough to read as the bar growing rather than as a different bar.
  static const Duration motion = Duration(milliseconds: 320);

  @override
  State<BrandPill> createState() => _BrandPillState();
}

class _BrandPillState extends State<BrandPill> {
  ConnectionNews? _news;

  /// Clears a status the pill was asked for, as opposed to one the
  /// connection announced — those are cleared by whoever announced
  /// them.
  Timer? _asked;

  /// How long a status sits there when somebody taps for it. The same
  /// few seconds the banner gives an announcement, so asking and being
  /// told look like one behaviour.
  static const Duration _hold = Duration(seconds: 3);

  /// Says where the server stands, because somebody asked.
  ///
  /// The wordmark is the one thing on every screen that is always in
  /// the same place, so it is where the question gets asked. Before,
  /// the answer only ever arrived unprompted — you could watch the
  /// dot on the avatar, or wait for the connection to change and hope
  /// you were looking.
  /// [online] is read during build and handed in, because
  /// `context.reachable` watches, and watching from a tap callback is
  /// reading the tree at a moment the tree is not being built.
  void _sayWhereWeStand({required bool online}) {
    final news = _news;
    if (news == null) return;
    final tone = online ? BrutTone.mint : BrutTone.coral;

    news.say(online ? 'Online' : 'Offline', offline: !online);
    _asked?.cancel();
    _asked = Timer(_hold, () {
      if (mounted) news.clear();
    });

    // The wash is the same colour as the word, so the flourish is part
    // of the answer rather than decoration over it.
    ColourPulse.show(context, colour: tone.fill(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final found = ConnectionNews.maybeOf(context);
    if (identical(found, _news)) return;
    // Undertaking to show it, so the floating pill stays away. Released
    // again on the way out, or this screen would go on claiming it from
    // under the next one.
    _news?.release();
    _news = found;
    _news?.claim();
  }

  @override
  void dispose() {
    _asked?.cancel();
    _news?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The department accent comes from the theme rather than from
    // state: main.dart puts it there, so every identity surface reads
    // one value.
    final accent = Theme.of(context).colorScheme.secondary;
    final message = _news?.message;
    final resting = message == null;

    final target = resting
        ? accent
        : (_news!.offline
              ? BrutTone.coral.fill(context)
              : BrutTone.mint.fill(context));

    // Watched here, in the build, and carried to the callback.
    final online = context.reachable != Reachable.offline;
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : BrandPill.motion;
    final canPop = Navigator.of(context).canPop();

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, colour, _) {
        final fill = colour ?? target;
        // Measured against whatever colour the pill is at this frame,
        // not against the one it is heading for: mid-fade the fill is
        // neither, and a word that picks its ink from the destination
        // can be the wrong one for half the animation.
        final ink = context.foregroundOn(fill);

        return BrutSurface(
          fill: fill,
          radius: AppRadius.pill,
          shadow: AppShadows.sm,
          // Even now the glyph has gone: it was inset on the left to
          // make room for the bolt.
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
          // Whether it has somewhere to go is a question the navigator
          // can already answer: anywhere with a route under it is a
          // screen you arrived at, and the way out is home.
          semanticLabel:
              message ?? (canPop ? 'Back to the dashboard' : 'SmartEvent'),
          // Somewhere to go, and it goes there. Nowhere to go — the
          // dashboard — and it answers the question the wordmark is
          // standing next to instead.
          onTap: () => canPop
              ? Navigator.of(context).popUntil((route) => route.isFirst)
              : _sayWhereWeStand(online: online),
          child: AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            // Grows to the right. The wordmark is the fixed point — it
            // is in the same place before, during and after, so the
            // eye reads the bar as extending rather than as sliding.
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The wordmark alone. The bolt was a second mark
                // beside the name, and the name is the mark.
                //
                // Flexible because the bell beside it grows: on a
                // 360dp phone a back button, this, an extended notice
                // pill and the avatar are about 38px too much. The
                // name shortens for the few seconds the notice is out
                // rather than the header striping.
                Flexible(
                  child: Text(
                    'SmartEvent',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.wordmark.copyWith(color: ink),
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(width: 7),
                  // A rule rather than a middle dot: the dot is how
                  // this app joins two halves of one label, and the
                  // connection is not half of the brand's name.
                  Container(
                    width: 1.5,
                    height: 13,
                    color: ink.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    message,
                    style: AppText.monoLabel.copyWith(fontSize: 11, color: ink),
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
