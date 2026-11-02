import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_settings.dart';
import '../state/sfx.dart';
import 'app_colors.dart';
import 'app_layout.dart';
import 'app_theme.dart';
import 'palette.dart';

/// The component kit for SmartEvent's soft-pop neo-brutalist UI.
///
/// Material's own widgets cannot draw a hard offset shadow — its elevation
/// is always a blur — so the pieces that must sit on a shadow and drop onto
/// it when pressed live here instead. Everything is built on
/// [BrutSurface]: one widget that owns the fill, the 2px outline, the
/// radius, the shadow and the press.

/// Which meaning a component carries. The fill follows from the meaning,
/// never the other way round.
enum BrutTone {
  /// White. The default for anything that isn't saying something.
  neutral,

  /// The brand, and primary actions. Follows the department accent.
  brand,

  /// Needs attention, pending, waiting.
  sun,

  /// Done, approved.
  mint,

  /// Urgent, rejected, over budget.
  coral,

  // The three department accents. They carry no status meaning — they
  // exist so an area can own a colour without borrowing one that already
  // means something.
  orange,
  violet,
  teal,

  /// Neutral emphasis: a selected segment, a confirmed destructive action.
  dark,
}

extension BrutToneColors on BrutTone {
  /// The solid fill. The accents are fixed; the neutral and dark ones
  /// follow the theme.
  Color fill(BuildContext context) {
    // The accents are held down on a dark canvas. At full strength they
    // are light sources rather than surfaces, and a screen carrying
    // three of them has nothing else left to look at.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      BrutTone.neutral => context.palette.surface,
      BrutTone.brand =>
        dark ? AppColors.brandDark : Theme.of(context).colorScheme.primary,
      BrutTone.sun => dark ? AppColors.sunDark : AppColors.sun,
      BrutTone.mint => dark ? AppColors.mintDark : AppColors.mint,
      BrutTone.coral => dark ? AppColors.coralDark : AppColors.coral,
      BrutTone.orange => dark ? AppColors.orangeDark : AppColors.orange,
      BrutTone.violet => dark ? AppColors.violetDark : AppColors.violet,
      BrutTone.teal => dark ? AppColors.tealDark : AppColors.teal,
      BrutTone.dark => context.palette.ink,
    };
  }

  /// The soft version, for a background sitting behind a paragraph.
  Color tint(BuildContext context) => switch (this) {
    BrutTone.neutral => context.palette.surface,
    BrutTone.brand => context.palette.brandTint,
    BrutTone.sun => context.palette.sunTint,
    BrutTone.mint => context.palette.mintTint,
    BrutTone.coral => context.palette.coralTint,
    BrutTone.orange => context.palette.orangeTint,
    BrutTone.violet => context.palette.violetTint,
    BrutTone.teal => context.palette.tealTint,
    BrutTone.dark => context.palette.line,
  };

  /// The foreground that belongs on this tone's fill — measured from the
  /// fill rather than declared, so it is right in either theme.
  Color foreground(BuildContext context) => context.foregroundOn(fill(context));
}

/// Fill, 2px outline, radius, hard shadow, and the press.
///
/// Pressing translates the surface by exactly its own shadow offset and
/// removes the shadow, so it lands on the mark it was floating above.
class BrutSurface extends StatefulWidget {
  const BrutSurface({
    super.key,
    required this.child,
    this.fill,
    this.radius = AppRadius.rowAll,
    this.shadow = AppShadows.base,
    this.side,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.width,
    this.height,
    this.alignment,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;

  /// Defaults to the theme's surface.
  final Color? fill;
  final BorderRadius radius;
  final List<BoxShadow> shadow;
  final BorderSide? side;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<BrutSurface> createState() => _BrutSurfaceState();
}

/// The tap sound, for anything pressable.
///
/// Every control in the kit is a BrutSurface underneath, so this is the
/// one place it has to be wired. A host with no player — a widget test —
/// simply gets silence.
void _sound(BuildContext context) {
  try {
    context.read<SfxPlayer>().play(Sfx.tap);
  } on ProviderNotFoundException {
    // Nothing to play through, which is not a reason to refuse the tap.
  }
}

class _BrutSurfaceState extends State<BrutSurface> {
  bool _down = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pressed = _down && _interactive;
    final fill = widget.enabled
        ? (widget.fill ?? palette.surface)
        : palette.line;
    // A disabled control has nothing to drop onto, so it loses its shadow
    // as well — the flatness is the signal.
    final shadow = pressed || !widget.enabled
        ? AppShadows.none
        : context.shadows(widget.shadow);
    final travel = pressed ? AppShadows.travelFor(widget.shadow) : Offset.zero;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : AppMotion.press;

    // The design's one structural rule: ink is the foreground for the
    // nearest background. Measuring the fill and handing the answer down
    // as the default text and icon colour is what makes a white button
    // inside a yellow card come out right, in either theme, however
    // deeply things nest.
    final foreground = widget.enabled
        ? context.foregroundOn(fill)
        : palette.subtle;

    Widget surface = AnimatedContainer(
      duration: duration,
      curve: AppMotion.pressed,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      alignment: widget.alignment,
      transform: Matrix4.translationValues(travel.dx, travel.dy, 0),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: widget.radius,
        border: Border.fromBorderSide(
          widget.side ?? (widget.enabled ? context.side : context.disabledSide),
        ),
        boxShadow: shadow,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: widget.child,
        ),
      ),
    );

    if (_interactive) {
      surface = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                // On the press itself rather than on the release, so it
                // lands with the shadow rather than after it.
                _sound(context);
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: surface,
      );
    }

    if (widget.semanticLabel != null) {
      surface = Semantics(
        label: widget.semanticLabel,
        button: _interactive,
        child: surface,
      );
    }
    return surface;
  }
}

enum BrutSize { small, medium, large }

/// A button that says exactly what happens when you press it.
class BrutButton extends StatelessWidget {
  const BrutButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.tone = BrutTone.brand,
    this.size = BrutSize.medium,
    this.busy = false,
    this.busyLabel,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final BrutTone tone;
  final BrutSize size;

  /// While busy the button disables itself and says what it is doing.
  final bool busy;
  final String? busyLabel;
  final bool expand;

  double get _height => switch (size) {
    BrutSize.small => 36,
    BrutSize.medium => 44,
    BrutSize.large => 52,
  };

  double get _fontSize => switch (size) {
    BrutSize.small => 13,
    BrutSize.medium => 14,
    BrutSize.large => 15,
  };

  double get _iconSize => size == BrutSize.small ? 16 : 18;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final foreground = enabled
        ? tone.foreground(context)
        : context.palette.subtle;
    final text = busy ? (busyLabel ?? label) : label;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: BrutSpinner(size: _iconSize, color: foreground),
          )
        else if (icon != null)
          Icon(icon, size: _iconSize, color: foreground),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.buttonLabel.copyWith(
              fontSize: _fontSize,
              color: foreground,
            ),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, size: _iconSize, color: foreground),
        ],
      ],
    );

    return BrutSurface(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      fill: tone.fill(context),
      radius: AppRadius.controlAll,
      shadow: AppShadows.base,
      height: _height,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: size == BrutSize.small ? 12 : 16,
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}

/// A 40x40 square with one icon. The icon is decorative; the label is on
/// the control, for anyone using a screen reader.
class BrutIconButton extends StatelessWidget {
  const BrutIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.tone = BrutTone.neutral,
    this.size = 40,
  });

  final IconData icon;

  /// Spoken, not shown.
  final String label;
  final VoidCallback? onPressed;
  final BrutTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return BrutSurface(
      onTap: onPressed,
      enabled: enabled,
      semanticLabel: label,
      fill: tone.fill(context),
      radius: AppRadius.controlAll,
      shadow: AppShadows.sm,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size * 0.45,
        color: enabled ? tone.foreground(context) : context.palette.subtle,
      ),
    );
  }
}

/// A container. Accent-filled when it is saying something, white when it
/// is only holding things.
class BrutCard extends StatelessWidget {
  const BrutCard({
    super.key,
    required this.child,
    this.tone = BrutTone.neutral,
    this.tinted = false,
    this.padding = const EdgeInsets.all(14),
    this.shadow = AppShadows.base,
    this.radius = AppRadius.cardAll,
    this.onTap,
  });

  final Widget child;
  final BrutTone tone;

  /// Use the soft version of the tone, for a card with a paragraph in it.
  final bool tinted;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow> shadow;
  final BorderRadius radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: onTap,
      fill: tinted ? tone.tint(context) : tone.fill(context),
      radius: radius,
      shadow: shadow,
      padding: padding,
      child: child,
    );
  }
}

/// A small state label. Always says the state in words as well as colour,
/// because colour alone is not a signal everyone receives.
class BrutBadge extends StatelessWidget {
  const BrutBadge({
    super.key,
    required this.label,
    this.tone = BrutTone.neutral,
    this.mono = false,
    this.dot = false,
  });

  final String label;
  final BrutTone tone;

  /// Mono uppercase, for counts and meta rather than states.
  final bool mono;

  /// A small leading dot, for live or urgent states.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final foreground = tone.foreground(context);
    return BrutSurface(
      fill: tone.fill(context),
      radius: AppRadius.controlAll,
      shadow: AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          // A badge is normally a word or two and sizes to its text. Some
          // labels are a sentence — "Rejected by <name>" — and where the
          // badge sits in a bounded row it would otherwise paint straight
          // through the edge of the card it is on. Ellipsis is a worse
          // label but a readable screen.
          Flexible(
            child: Text(
              mono ? label.toUpperCase() : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? AppText.monoLabel.copyWith(color: foreground)
                  : AppText.buttonLabel.copyWith(
                      fontSize: 11,
                      color: foreground,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The universal eyebrow: `PENDING ADVISER`, `STEP 02 / 04`, `CITE · OFFICER`.
/// Separate parts with a middle dot.
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.color, this.fontSize});

  final String text;
  final Color? color;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppText.monoLabel.copyWith(color: color, fontSize: fontSize),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A rounded square holding one icon. Marks what a card or row is about.
class BrutIconTile extends StatelessWidget {
  const BrutIconTile({
    super.key,
    required this.icon,
    this.tone = BrutTone.neutral,
    this.size = 36,
  });

  final IconData icon;
  final BrutTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.fill(context),
        borderRadius: size >= 40 ? AppRadius.rowAll : AppRadius.controlAll,
        border: context.borderAll,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: tone.foreground(context)),
    );
  }
}

/// A full-width row: a marker, a title with one meta line, an optional
/// value on the right, and a chevron when it opens something.
class BrutListRow extends StatelessWidget {
  const BrutListRow({
    super.key,
    required this.title,
    this.meta,
    this.marker,
    this.trailing,
    this.onTap,
    this.tone = BrutTone.neutral,
  });

  final String title;
  final String? meta;
  final Widget? marker;
  final Widget? trailing;
  final VoidCallback? onTap;
  final BrutTone tone;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: onTap,
      fill: tone.fill(context),
      radius: AppRadius.rowAll,
      shadow: AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (marker != null) ...[marker!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  MonoLabel(meta!),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: context.palette.subtle),
          ],
        ],
      ),
    );
  }
}

/// A number worth looking at, filled with the status colour of the number
/// itself. Always tappable, because a number nobody can explain is noise.
class BrutMetricTile extends StatelessWidget {
  const BrutMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.tone = BrutTone.neutral,
    this.onTap,
    this.footnote,
  });

  final String label;
  final String value;
  final BrutTone tone;
  final VoidCallback? onTap;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final foreground = tone.foreground(context);
    return BrutSurface(
      onTap: onTap,
      fill: tone.fill(context),
      radius: AppRadius.rowAll,
      shadow: AppShadows.base,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: MonoLabel(label, color: foreground)),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 16, color: foreground),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppText.moneyLarge.copyWith(color: foreground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(footnote!, style: AppText.caption.copyWith(color: foreground)),
          ],
        ],
      ),
    );
  }
}

/// A 12px pill with a 2px divider where the fill ends, so the boundary is
/// a line rather than a colour change.
class BrutProgressBar extends StatelessWidget {
  const BrutProgressBar({
    super.key,
    required this.value,
    this.tone = BrutTone.brand,
    this.height = 12,
  });

  /// 0..1. Clamped, so an over-budget ratio shows a full bar rather than
  /// overflowing the container.
  final double value;
  final BrutTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ratio = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.palette.line,
        borderRadius: AppRadius.pill,
        border: context.borderAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: ratio,
          child: Container(
            decoration: BoxDecoration(
              color: tone.fill(context),
              border: ratio > 0 && ratio < 1
                  ? Border(right: context.side)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing here yet, said in a box that looks deliberately unfinished
/// rather than broken.
class BrutEmptyState extends StatelessWidget {
  const BrutEmptyState({
    super.key,
    required this.title,
    this.hint,
    this.icon,
    this.action,
  });

  final String title;
  final String? hint;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        radius: AppRadius.row,
        ink: context.palette.ink,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 32, color: context.palette.muted),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              style: AppText.cardTitle.copyWith(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint!, style: AppText.caption, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius, required this.ink});

  final double radius;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: 0.4)
      ..strokeWidth = AppBorders.width
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    // Walk the outline and draw only every other 6px stretch.
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.ink != ink;
}

/// A sentence in a tinted box, next to the thing it is about. Errors use
/// this; so does a success note that should stay on screen.
class BrutInlineMessage extends StatelessWidget {
  const BrutInlineMessage({
    super.key,
    required this.text,
    this.tone = BrutTone.sun,
    this.icon,
  });

  final String text;
  final BrutTone tone;
  final IconData? icon;

  bool get _isError => tone == BrutTone.coral;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.tint(context),
          borderRadius: AppRadius.controlAll,
          border: context.borderAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: context.palette.ink),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                text,
                style: AppText.body.copyWith(
                  fontSize: 12.5,
                  color: _isError
                      ? context.palette.alertInk
                      : context.palette.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section heading with an optional count or action on the right.
/// A section that can be folded away.
///
/// Three screens asked for the same thing: a stack of warnings you have
/// read and no longer want occupying the screen. Folding is per section
/// and lasts the life of the screen rather than being persisted — a
/// blocker that comes back deserves to be seen again.
///
/// The header always carries the count, so a folded section still says
/// what it is hiding.
class BrutFoldable extends StatefulWidget {
  const BrutFoldable({
    super.key,
    required this.title,
    required this.children,
    this.count,
    this.initiallyOpen = true,
  });

  final String title;
  final List<Widget> children;
  final int? count;
  final bool initiallyOpen;

  @override
  State<BrutFoldable> createState() => _BrutFoldableState();
}

class _BrutFoldableState extends State<BrutFoldable> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.count == null
              ? widget.title
              : '${widget.title}, ${widget.count}',
          child: GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: AppText.sectionTitle),
                  ),
                  if (widget.count != null) ...[
                    MonoLabel('${widget.count}'),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: context.palette.subtle,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.accordion,
          curve: AppMotion.inPlace,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppLayout.between),
                    ...widget.children,
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The app's own spinner.
///
/// A ring carrying the two accents — blue leading, orange following —
/// turning in steps rather than sweeping. The kit has no easing in its
/// loading states anywhere else, and a smooth Material ring in the
/// middle of it looked borrowed. Twelve stops a second reads as
/// deliberate rather than stuttering.
///
/// Reduce motion stops the rotation and leaves the ring, because the
/// point is "this is working", not the spinning.
class BrutSpinner extends StatefulWidget {
  const BrutSpinner({
    super.key,
    this.size = 34,
    this.tone = BrutTone.brand,
    this.color,
  });

  final double size;
  final BrutTone tone;

  /// Overrides both arcs with one colour, for a spinner sitting on a
  /// coloured fill that has already decided what its ink is — a busy
  /// button, say, where two accents would fight the button under them.
  final Color? color;

  @override
  State<BrutSpinner> createState() => _BrutSpinnerState();
}

class _BrutSpinnerState extends State<BrutSpinner>
    with SingleTickerProviderStateMixin {
  /// The ring lands on each twelfth rather than sliding between them,
  /// which keeps the mechanical tick the rest of the kit has.
  static const _stops = 12;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        context.watch<AppSettings>().reduceMotion;

    // The app's two accents, chasing each other: blue leads, orange
    // follows. Which is also how the areas are coloured, so a spinner
    // looks like it belongs to this app rather than to Material.
    final one = widget.color ?? (dark ? AppColors.brandDark : AppColors.brand);
    final two =
        widget.color ?? (dark ? AppColors.orangeDark : AppColors.orange);

    final painter = _SpinnerPainter(
      first: one,
      second: two,
      track: context.palette.line,
      outline: context.palette.ink,
      // Thin rings look weedy next to 2px rules; a small one drops the
      // outline instead of shrinking the stroke to nothing.
      stroke: widget.size < 22 ? 3.0 : 5.0,
      outlined: widget.size >= 22,
    );

    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: still
            ? CustomPaint(painter: painter)
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final step = (_controller.value * _stops).floor() / _stops;
                  return Transform.rotate(
                    angle: step * 2 * math.pi,
                    child: CustomPaint(painter: painter),
                  );
                },
              ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({
    required this.first,
    required this.second,
    required this.track,
    required this.outline,
    required this.stroke,
    required this.outlined,
  });

  final Color first;
  final Color second;
  final Color track;
  final Color outline;
  final double stroke;
  final bool outlined;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = outlined ? stroke / 2 + 1 : stroke / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // The whole ring first, so the gap between the arcs reads as part of
    // the shape rather than as nothing.
    canvas.drawArc(rect, 0, 2 * math.pi, false, ring..color = track);

    const sweep = math.pi * 0.62;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, ring..color = first);
    canvas.drawArc(rect, math.pi / 2, sweep, false, ring..color = second);

    if (!outlined) return;

    // The kit's outline, inside and out, so the ring reads as drawn
    // rather than as a glow.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = outline;
    canvas.drawCircle(rect.center, rect.width / 2 + stroke / 2, edge);
    canvas.drawCircle(rect.center, rect.width / 2 - stroke / 2, edge);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.first != first ||
      old.second != second ||
      old.track != track ||
      old.outline != outline ||
      old.stroke != stroke ||
      old.outlined != outlined;
}

class BrutSectionTitle extends StatelessWidget {
  const BrutSectionTitle(this.title, {super.key, this.aside});

  final String title;
  final Widget? aside;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppText.sectionTitle)),
        ?aside,
      ],
    );
  }
}

/// The frame every screen is built in.
///
/// A fixed header, one scrolling area with the standard gutters, and a
/// docked footer. Screens used to each pick their own padding — there
/// were twelve different combinations — which is the kind of thing nobody
/// notices one screen at a time and everybody notices flipping between
/// them.
class BrutScreen extends StatelessWidget {
  const BrutScreen({
    super.key,
    required this.child,
    this.header,
    this.topBar,
    this.footer,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.scrollable = true,
    this.bottomPadding = AppLayout.contentPadding,
  });

  /// A [BrutHeader] or [BrutFlowHeader], drawn edge to edge with its own
  /// padding and its own 2px rule.
  final Widget? header;

  /// A header that sits inside the gutters instead — the app's top bar,
  /// with the brand pill and the avatar.
  final Widget? topBar;

  /// The content. Gets the side gutters either way; gets a scroll view
  /// too unless [scrollable] is false, in which case it is expanded as it
  /// is and manages its own.
  final Widget child;
  final Widget? footer;
  final Widget? floatingActionButton;

  /// Where that button sits. The default is the corner; a screen with
  /// one unmistakable action centres it instead.
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool scrollable;

  /// Room under the content, for a screen with a floating button over it.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final gutters = EdgeInsets.fromLTRB(
      AppLayout.gutter,
      AppLayout.contentPadding,
      AppLayout.gutter,
      bottomPadding,
    );

    return Scaffold(
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: SafeArea(
        // The footer handles the bottom inset itself, so the safe area
        // must not also pad it or the gap doubles.
        bottom: false,
        child: Column(
          children: [
            ?header,
            if (topBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppLayout.gutter,
                  AppLayout.headerTopPadding,
                  AppLayout.gutter,
                  0,
                ),
                child: topBar,
              ),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(padding: gutters, child: child)
                  : Padding(padding: gutters.copyWith(bottom: 0), child: child),
            ),
            ?footer,
          ],
        ),
      ),
    );
  }
}

/// A screen header: a 40px back button tinted with the area's accent, a
/// mono eyebrow over a one-line title, an optional action, and the 2px
/// rule that separates it from the content.
class BrutHeader extends StatelessWidget {
  const BrutHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.onBack,
    this.action,
    this.tone = BrutTone.brand,
  });

  final String title;
  final String? eyebrow;
  final VoidCallback? onBack;
  final Widget? action;
  final BrutTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.headerTopPadding,
        AppLayout.gutter,
        AppLayout.headerBottomPadding,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        border: context.borderBottom,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            BrutIconButton(
              icon: Icons.arrow_back,
              label: 'Back',
              tone: tone,
              size: AppLayout.iconButton,
              onPressed: onBack,
            ),
            const SizedBox(width: AppLayout.between),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[
                  MonoLabel(eyebrow!),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: AppText.screenTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppLayout.between),
            action!,
          ],
        ],
      ),
    );
  }
}

/// One step of a multi-step task.
class BrutStep {
  const BrutStep({required this.label, this.onJump});

  /// Shown under its bar, in mono.
  final String label;

  /// Set only once the step can be reached. A bar with nothing behind it
  /// is not a button.
  final VoidCallback? onJump;
}

/// A header for a task that runs in steps: the usual header, plus a row
/// of bars that say how far along you are and let you go back to a step
/// you have already passed.
class BrutFlowHeader extends StatelessWidget {
  const BrutFlowHeader({
    super.key,
    required this.title,
    required this.steps,
    required this.currentStep,
    this.flowName,
    this.onBack,
    this.action,
    this.tone = BrutTone.brand,
  });

  final String title;
  final List<BrutStep> steps;

  /// Zero-based.
  final int currentStep;

  /// Named in the eyebrow beside the step count.
  final String? flowName;
  final VoidCallback? onBack;
  final Widget? action;
  final BrutTone tone;

  String get _eyebrow {
    final counted =
        'Step ${(currentStep + 1).toString().padLeft(2, '0')} / '
        '${steps.length.toString().padLeft(2, '0')}';
    return flowName == null ? counted : '$counted · $flowName';
  }

  @override
  Widget build(BuildContext context) {
    final accent = tone.fill(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.headerTopPadding,
        AppLayout.gutter,
        AppLayout.headerBottomPadding,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        border: context.borderBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                BrutIconButton(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  tone: tone,
                  size: AppLayout.iconButton,
                  onPressed: onBack,
                ),
                const SizedBox(width: AppLayout.between),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MonoLabel(_eyebrow),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: AppText.screenTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: AppLayout.between),
                action!,
              ],
            ],
          ),
          const SizedBox(height: AppLayout.stepBarTopGap),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      BrutSurface(
                        onTap: steps[i].onJump,
                        semanticLabel: steps[i].label,
                        fill: i <= currentStep ? accent : context.palette.line,
                        radius: AppRadius.pill,
                        shadow: AppShadows.none,
                        // Without an explicit width the bar shrinks to its
                        // (empty) child and renders as a dot.
                        width: double.infinity,
                        height: AppLayout.stepBarHeight,
                        child: const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        steps[i].label.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.monoLabel.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                          color: i == currentStep
                              ? context.palette.ink
                              : context.palette.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != steps.length - 1)
                  const SizedBox(width: AppLayout.stepBarGap),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A docked footer for the primary action, clear of the system gesture
/// area, separated from the content by the 2px rule.
///
/// With [onBack] it becomes the standard pair: a square back button and a
/// full-width primary action beside it. A second action goes on its own
/// row rather than being squeezed into the same one, so it never
/// overlaps on a narrow phone.
class BrutFooter extends StatelessWidget {
  const BrutFooter({
    super.key,
    required this.child,
    this.onBack,
    this.secondary,
    this.note,
  });

  final Widget child;

  /// Draws the square back button beside [child].
  final VoidCallback? onBack;

  /// A second, lesser action, on its own row underneath.
  final Widget? secondary;

  /// A mono line above everything — "Paper 1 of 6", "2 answers are not
  /// confirmed yet".
  final String? note;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.footerTopPadding,
        AppLayout.gutter,
        inset > AppLayout.footerBottomPadding
            ? inset
            : AppLayout.footerBottomPadding,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        border: context.borderTop,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) ...[
            MonoLabel(note!),
            const SizedBox(height: AppLayout.tight),
          ],
          if (onBack == null)
            child
          else
            Row(
              children: [
                SizedBox(
                  width: AppLayout.footerAction,
                  height: AppLayout.footerAction,
                  child: BrutIconButton(
                    icon: Icons.arrow_back,
                    label: 'Back',
                    size: AppLayout.footerAction,
                    onPressed: onBack,
                  ),
                ),
                const SizedBox(width: AppLayout.between),
                Expanded(child: child),
              ],
            ),
          if (secondary != null) ...[
            const SizedBox(height: AppLayout.tight),
            secondary!,
          ],
        ],
      ),
    );
  }
}

/// The app's one bottom sheet.
///
/// Every sheet in the app is this: never taller than 85% of the screen,
/// a header with the title and a close X, a body that scrolls, and a
/// footer that stays put. Seven screens each had their own copy of the
/// container before this.
class BrutSheet extends StatelessWidget {
  const BrutSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
  });

  final String title;

  /// A sentence under the title, for a sheet that has to explain itself.
  final String? subtitle;
  final Widget child;

  /// Stays visible while the body scrolls.
  final Widget? footer;

  /// Opens [builder] as the app's standard sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height *
              AppLayout.sheetMaxHeightFraction,
        ),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          border: context.borderAll,
          boxShadow: context.shadows(AppShadows.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppLayout.sheetSidePadding,
                AppLayout.sheetVerticalPadding,
                AppLayout.sheetVerticalPadding,
                AppLayout.sheetVerticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BrutSectionTitle(title),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: AppText.caption),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppLayout.tight),
                  BrutIconButton(
                    icon: Icons.close,
                    label: 'Close',
                    size: 32,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppLayout.sheetSidePadding,
                  0,
                  AppLayout.sheetSidePadding,
                  footer == null
                      ? AppLayout.section +
                            MediaQuery.viewPaddingOf(context).bottom
                      : AppLayout.contentPadding,
                ),
                child: child,
              ),
            ),
            if (footer != null)
              Container(
                padding: EdgeInsets.fromLTRB(
                  AppLayout.sheetSidePadding,
                  AppLayout.footerTopPadding,
                  AppLayout.sheetSidePadding,
                  AppLayout.footerBottomPadding +
                      MediaQuery.viewPaddingOf(context).bottom,
                ),
                decoration: BoxDecoration(border: context.borderTop),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the app a phone-width column on a tablet or a desktop window,
/// like a phone sitting on a desk, instead of stretching a one-hand
/// layout across 1400px.
class AppColumn extends StatelessWidget {
  const AppColumn({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.columnMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= maxWidth) return child;

    return ColoredBox(
      color: context.palette.backdrop,
      child: Center(
        child: Container(
          width: maxWidth,
          decoration: BoxDecoration(
            color: context.palette.canvas,
            border: Border(left: context.side, right: context.side),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A text field that gains its shadow on focus and tints coral when it has
/// an error, with the message underneath in [context.palette.alertInk] — coral
/// itself is a fill colour and cannot be read at 12px.
class BrutTextField extends StatefulWidget {
  const BrutTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.prefixIcon,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
  });

  /// A mono eyebrow above the field.
  final String? label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final IconData? prefixIcon;
  final int maxLines;

  /// A hard cap, enforced as you type. The counter is hidden — the limit
  /// is a guard rail, not a target.
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;

  @override
  State<BrutTextField> createState() => _BrutTextFieldState();
}

class _BrutTextFieldState extends State<BrutTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final fill = !widget.enabled
        ? context.palette.line
        : hasError
        ? context.palette.coralTint
        : context.palette.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          MonoLabel(widget.label!),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? const Duration(milliseconds: 1)
              : AppMotion.press,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppRadius.controlAll,
            border: Border.fromBorderSide(
              widget.enabled ? context.side : context.disabledSide,
            ),
            // A field rests on a small shadow and lifts onto the full one
            // when it takes focus, so the active field is obvious without
            // a colour change.
            boxShadow: context.shadows(
              _focus.hasFocus ? AppShadows.base : AppShadows.sm,
            ),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            maxLength: widget.maxLength,
            buildCounter:
                (
                  _, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) => null,
            autofocus: widget.autofocus,
            textCapitalization: widget.textCapitalization,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            cursorColor: context.palette.ink,
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppText.body.copyWith(color: context.palette.muted),
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(
                      widget.prefixIcon,
                      size: 18,
                      color: context.palette.subtle,
                    ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 38,
              ),
              suffixIcon: widget.suffix,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: AppText.caption.copyWith(
              color: context.palette.alertInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// A picker that opens a sheet of choices rather than a native dropdown.
///
/// The design asks for this because a native menu cannot show a long,
/// colour-coded list legibly, and because a row with room for a check
/// mark reads as a choice in a way a menu line does not. The API is the
/// same as a `DropdownButton` — value, items, onChanged — so every call
/// site in the app passes the `DropdownMenuItem`s it already had.
class BrutDropdown<T> extends StatelessWidget {
  const BrutDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  /// A mono eyebrow above the control.
  final String? label;
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  bool get _live => enabled && onChanged != null && items.isNotEmpty;

  Future<void> _open(BuildContext context) async {
    final chosen = await BrutSheet.show<T>(
      context,
      builder: (_) =>
          _ChoiceSheet<T>(title: label ?? hint, value: value, items: items),
    );
    // Null means dismissed, which is not the same as choosing nothing.
    if (chosen != null) onChanged?.call(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final current = items.where((i) => i.value == value).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[MonoLabel(label!), const SizedBox(height: 6)],
        BrutSurface(
          onTap: _live ? () => _open(context) : null,
          enabled: _live,
          semanticLabel: label,
          radius: AppRadius.controlAll,
          shadow: AppShadows.sm,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: current == null
                    ? Text(
                        hint,
                        style: AppText.body.copyWith(
                          color: context.palette.muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : DefaultTextStyle.merge(
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: current.child,
                      ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.value,
    required this.items,
  });

  final String title;
  final T? value;
  final List<DropdownMenuItem<T>> items;

  @override
  Widget build(BuildContext context) {
    return BrutSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _ChoiceRow<T>(item: items[i], selected: items[i].value == value),
            if (i != items.length - 1) const SizedBox(height: AppLayout.tight),
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.item, required this.selected});

  final DropdownMenuItem<T> item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: () => Navigator.of(context).pop(item.value),
      fill: selected ? Theme.of(context).colorScheme.primary : null,
      radius: AppRadius.rowAll,
      shadow: selected ? AppShadows.base : AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style: AppText.body.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: item.child,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: AppLayout.tight),
            const Icon(Icons.check, size: 18),
          ],
        ],
      ),
    );
  }
}

/// A filter chip. Selected takes the area accent with ink on it;
/// unselected is a plain outline with no shadow, so a row of chips reads
/// as one chosen and the rest available.
///
/// A chip with no [onTap] is disabled: flat and muted, silent, and read as
/// disabled by a screen reader. Pass a callback only when a tap does something.
class BrutChip extends StatelessWidget {
  const BrutChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Defaults to the area accent.
  final BrutTone? tone;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? (tone ?? BrutTone.brand).fill(context)
        : context.palette.surface;

    final chip = BrutSurface(
      onTap: onTap,
      enabled: onTap != null,
      fill: fill,
      radius: AppRadius.controlAll,
      shadow: selected ? AppShadows.sm : AppShadows.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppText.buttonLabel.copyWith(
          fontSize: 12,
          color: selected ? context.palette.ink : context.palette.subtle,
        ),
      ),
    );

    // BrutSurface draws a disabled control but says nothing about it, so a
    // screen reader would offer this as a live chip.
    return onTap == null ? Semantics(enabled: false, child: chip) : chip;
  }
}

/// A horizontally scrolling row of [BrutChip]s, bleeding to the screen
/// edge so it is obvious there is more to the right.
class BrutChipBar extends StatelessWidget {
  const BrutChipBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// A date, picked rather than typed. Looks like a field, behaves like a
/// button — the hint shows until a date is chosen.
class BrutDateField extends StatelessWidget {
  const BrutDateField({
    super.key,
    required this.value,
    required this.hint,
    required this.onTap,
    this.label,
  });

  final String? label;
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;

  static String format(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}'
      '-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final text = value == null ? hint : format(value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[MonoLabel(label!), const SizedBox(height: 6)],
        BrutSurface(
          onTap: onTap,
          radius: AppRadius.controlAll,
          shadow: AppShadows.sm,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: value == null
                      ? AppText.body.copyWith(color: context.palette.muted)
                      : AppText.number,
                ),
              ),
              const Icon(Icons.calendar_today_outlined, size: 16),
            ],
          ),
        ),
      ],
    );
  }
}

/// A load that failed, with the one action that might help.
///
/// An expired session is the exception: retrying a dead token just fails
/// again, so it says what to do instead of offering a button that cannot
/// work.
class BrutRetry extends StatelessWidget {
  const BrutRetry({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.sessionExpired = false,
  });

  final String title;
  final String? message;
  final VoidCallback onRetry;
  final bool sessionExpired;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: BrutEmptyState(
          icon: Icons.cloud_off_outlined,
          title: title,
          hint: message,
          action: sessionExpired
              ? const Text(
                  'Sign out and sign in again to continue.',
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                )
              : BrutButton(
                  label: 'Try again',
                  icon: Icons.refresh,
                  size: BrutSize.small,
                  expand: false,
                  tone: BrutTone.neutral,
                  onPressed: onRetry,
                ),
        ),
      ),
    );
  }
}

/// A label on the left, its value right-aligned opposite. Detail cards
/// across the app use this so their columns line up with each other.
class BrutDetailRow extends StatelessWidget {
  const BrutDetailRow(this.label, this.value, {super.key, this.mono = false});

  final String label;
  final String value;

  /// For amounts, quantities and dates.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: MonoLabel(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: mono
                ? AppText.number
                : AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
