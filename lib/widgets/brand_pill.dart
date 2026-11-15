import 'package:flutter/material.dart';

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
          padding: const EdgeInsets.fromLTRB(10, 5, 14, 5),
          // Whether it has somewhere to go is a question the navigator
          // can already answer: anywhere with a route under it is a
          // screen you arrived at, and the way out is home.
          semanticLabel: message ??
              (canPop ? 'Back to the dashboard' : 'SmartEvent'),
          onTap: () => canPop
              ? Navigator.of(context).popUntil((route) => route.isFirst)
              : ColourPulse.show(context),
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
                Icon(Icons.bolt, size: 15, color: ink),
                const SizedBox(width: 5),
                Text('SmartEvent', style: AppText.wordmark.copyWith(color: ink)),
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
                    style: AppText.monoLabel.copyWith(
                      fontSize: 11,
                      color: ink,
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
