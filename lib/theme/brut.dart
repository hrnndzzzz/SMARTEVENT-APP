import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_theme.dart';

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

  /// Neutral emphasis: a selected segment, a confirmed destructive action.
  dark,
}

extension BrutToneColors on BrutTone {
  /// The solid fill.
  Color fill(BuildContext context) => switch (this) {
        BrutTone.neutral => AppColors.surface,
        BrutTone.brand => Theme.of(context).colorScheme.primary,
        BrutTone.sun => AppColors.sun,
        BrutTone.mint => AppColors.mint,
        BrutTone.coral => AppColors.coral,
        BrutTone.dark => AppColors.ink,
      };

  /// The soft version, for a background sitting behind a paragraph.
  Color tint(BuildContext context) => switch (this) {
        BrutTone.neutral => AppColors.surface,
        BrutTone.brand => AppColors.brandTint,
        BrutTone.sun => AppColors.sunTint,
        BrutTone.mint => AppColors.mintTint,
        BrutTone.coral => AppColors.coralTint,
        BrutTone.dark => AppColors.line,
      };

  /// Ink on every accent — they are all light enough for it. Only the
  /// dark tone flips, and it flips all the way to the surface colour.
  Color get foreground =>
      this == BrutTone.dark ? AppColors.surface : AppColors.ink;
}

/// Fill, 2px outline, radius, hard shadow, and the press.
///
/// Pressing translates the surface by exactly its own shadow offset and
/// removes the shadow, so it lands on the mark it was floating above.
class BrutSurface extends StatefulWidget {
  const BrutSurface({
    super.key,
    required this.child,
    this.fill = AppColors.surface,
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
  final Color fill;
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

class _BrutSurfaceState extends State<BrutSurface> {
  bool _down = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  Widget build(BuildContext context) {
    final pressed = _down && _interactive;
    // A disabled control has nothing to drop onto, so it loses its shadow
    // as well — the flatness is the signal.
    final shadow =
        pressed || !widget.enabled ? AppShadows.none : widget.shadow;
    final travel =
        pressed ? AppShadows.travelFor(widget.shadow) : Offset.zero;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : AppMotion.press;

    Widget surface = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      alignment: widget.alignment,
      transform: Matrix4.translationValues(travel.dx, travel.dy, 0),
      decoration: BoxDecoration(
        color: widget.enabled ? widget.fill : AppColors.line,
        borderRadius: widget.radius,
        border: Border.fromBorderSide(
          widget.side ??
              (widget.enabled ? AppBorders.side : AppBorders.disabled),
        ),
        boxShadow: shadow,
      ),
      child: widget.child,
    );

    if (_interactive) {
      surface = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
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
    final foreground = enabled ? tone.foreground : AppColors.subtle;
    final text = busy ? (busyLabel ?? label) : label;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
            ),
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
            style: AppText.buttonLabel
                .copyWith(fontSize: _fontSize, color: foreground),
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
      padding: EdgeInsets.symmetric(horizontal: size == BrutSize.small ? 12 : 16),
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
        color: enabled ? tone.foreground : AppColors.subtle,
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
    final foreground = tone.foreground;
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
          Text(
            mono ? label.toUpperCase() : label,
            style: mono
                ? AppText.monoLabel.copyWith(color: foreground)
                : AppText.buttonLabel
                    .copyWith(fontSize: 11, color: foreground),
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
        borderRadius:
            size >= 40 ? AppRadius.rowAll : AppRadius.controlAll,
        border: AppBorders.all,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: tone.foreground),
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
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.subtle),
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
    final foreground = tone.foreground;
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
            Text(
              footnote!,
              style: AppText.caption.copyWith(color: foreground),
            ),
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
        color: AppColors.line,
        borderRadius: AppRadius.pill,
        border: AppBorders.all,
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
                  ? const Border(right: AppBorders.side)
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
      painter: _DashedBorderPainter(radius: AppRadius.row),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 32, color: AppColors.muted),
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
  const _DashedBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.4)
      ..strokeWidth = AppBorders.width
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));

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
      oldDelegate.radius != radius;
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
          border: AppBorders.all,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.ink),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                text,
                style: AppText.body.copyWith(
                  fontSize: 12.5,
                  color: _isError ? AppColors.alertInk : AppColors.ink,
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

/// A screen header: a back button tinted with the area's accent, a mono
/// eyebrow over a one-line title, an optional action, and the 2px rule
/// that separates it from the content.
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: AppBorders.bottom,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            BrutIconButton(
              icon: Icons.arrow_back,
              label: 'Back',
              tone: tone,
              onPressed: onBack,
            ),
            const SizedBox(width: 12),
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
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

/// A docked footer for the primary action, clear of the system gesture
/// area, separated from the content by the 2px rule.
class BrutFooter extends StatelessWidget {
  const BrutFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, inset > 12 ? inset : 12),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: AppBorders.top,
      ),
      child: child,
    );
  }
}

/// Keeps the app a phone-width column on a tablet or a desktop window,
/// like a phone sitting on a desk, instead of stretching a one-hand
/// layout across 1400px.
class AppColumn extends StatelessWidget {
  const AppColumn({super.key, required this.child, this.maxWidth = 420});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= maxWidth) return child;

    return ColoredBox(
      color: AppColors.backdrop,
      child: Center(
        child: Container(
          width: maxWidth,
          decoration: const BoxDecoration(
            color: AppColors.canvas,
            border: Border(left: AppBorders.side, right: AppBorders.side),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A text field that gains its shadow on focus and tints coral when it has
/// an error, with the message underneath in [AppColors.alertInk] — coral
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
        ? AppColors.line
        : hasError
            ? AppColors.coralTint
            : AppColors.surface;

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
              widget.enabled ? AppBorders.side : AppBorders.disabled,
            ),
            // A field rests on a small shadow and lifts onto the full one
            // when it takes focus, so the active field is obvious without
            // a colour change.
            boxShadow: _focus.hasFocus ? AppShadows.base : AppShadows.sm,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            autofocus: widget.autofocus,
            textCapitalization: widget.textCapitalization,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            cursorColor: AppColors.ink,
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppText.body.copyWith(color: AppColors.muted),
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
                  : Icon(widget.prefixIcon, size: 18, color: AppColors.subtle),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 38, minHeight: 38),
              suffixIcon: widget.suffix,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: AppText.caption.copyWith(
              color: AppColors.alertInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// A dropdown styled like the rest of the system.
///
/// The design would rather this opened a bottom sheet of choice rows, and
/// for a long colour-coded list that is better. It stays a native
/// dropdown here because every picker in the app — school year, semester,
/// scope, category, department, movement type — would have to change
/// behaviour at once, and several are covered by widget tests that tap
/// them. Converting them is a separate, testable change.
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

  @override
  Widget build(BuildContext context) {
    final live = enabled && onChanged != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          MonoLabel(label!),
          const SizedBox(height: 6),
        ],
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: live ? AppColors.surface : AppColors.line,
            borderRadius: AppRadius.controlAll,
            border: Border.fromBorderSide(
              live ? AppBorders.side : AppBorders.disabled,
            ),
            boxShadow: live ? AppShadows.sm : AppShadows.none,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              items: items,
              onChanged: live ? onChanged : null,
              icon: Icon(
                Icons.expand_more,
                size: 20,
                color: live ? AppColors.ink : AppColors.muted,
              ),
              borderRadius: AppRadius.rowAll,
              dropdownColor: AppColors.surface,
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              hint: Text(
                hint,
                style: AppText.body.copyWith(color: AppColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
