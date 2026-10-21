import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/avatar.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Somebody's picture, wherever it appears.
///
/// The ink on it is always dark and the grounds are always light, so the
/// picture is the same mark in either theme — a face that changed colour
/// with the time of day would not read as the same person.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.size = 38,
    this.style,
    this.color,
    this.pattern,
    this.photo,
  });

  final String name;
  final double size;

  /// Overrides, for the editor's live preview. Everything omitted comes
  /// from what is stored.
  final AvatarStyle? style;
  final int? color;
  final AvatarPattern? pattern;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    // Everything here can be derived from the name alone, so a context
    // with no stored picture — a test, a screen hosted on its own —
    // still draws a real avatar rather than throwing.
    Avatar? stored;
    try {
      stored = context.watch<Avatar>();
    } on ProviderNotFoundException {
      stored = null;
    }

    final chosen = style ?? stored?.style ?? AvatarStyle.initials;
    final ground = Color(
      color ??
          stored?.colorFor(name) ??
          avatarColors[avatarSeed(name) % avatarColors.length],
    );
    final mark = pattern ?? stored?.patternFor(name) ?? AvatarPattern.blocks;
    final image = photo ?? stored?.photo;

    Widget inner;
    if (chosen == AvatarStyle.photo && image != null) {
      inner = Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (chosen == AvatarStyle.pattern) {
      inner = CustomPaint(
        painter: _PatternPainter(
          pattern: mark,
          seed: avatarSeed(name),
          ground: ground,
        ),
        size: Size.square(size),
      );
    } else {
      inner = ColoredBox(
        color: ground,
        child: Center(
          child: Text(
            Avatar.initialsFor(name),
            style: AppText.number.copyWith(
              // 36% of the circle, so two letters sit the same in a
              // header and in the editor's large preview.
              fontSize: size * 0.36,
              color: AppColors.ink,
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: inner,
    );
  }
}

/// The eight marks.
///
/// Each is laid out from the name's seed, so the same person keeps the
/// same arrangement and two people sharing a pattern and a colour still
/// look different. Drawn rather than drawn from assets: eight images at
/// eight colours would be sixty-four files to ship.
class _PatternPainter extends CustomPainter {
  const _PatternPainter({
    required this.pattern,
    required this.seed,
    required this.ground,
  });

  final AvatarPattern pattern;
  final int seed;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = ground);

    final ink = Paint()..color = AppColors.ink.withValues(alpha: 0.78);
    final rng = math.Random(seed);
    final w = size.width;

    switch (pattern) {
      case AvatarPattern.blocks:
        // Mirrored down the middle, the way an identicon reads as a face.
        const cells = 5;
        final cell = w / cells;
        for (var y = 0; y < cells; y++) {
          for (var x = 0; x < (cells / 2).ceil(); x++) {
            if (rng.nextBool()) continue;
            for (final dx in {x, cells - 1 - x}) {
              canvas.drawRect(
                Rect.fromLTWH(dx * cell, y * cell, cell, cell),
                ink,
              );
            }
          }
        }
      case AvatarPattern.dots:
        final step = w / 4;
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            final r = step * (0.14 + rng.nextDouble() * 0.2);
            canvas.drawCircle(
              Offset((x + 0.5) * step, (y + 0.5) * step),
              r,
              ink,
            );
          }
        }
      case AvatarPattern.stripes:
        final band = w / 7;
        for (var i = 0; i < 7; i++) {
          if (i.isEven) continue;
          canvas.drawRect(Rect.fromLTWH(i * band, 0, band, size.height), ink);
        }
      case AvatarPattern.waves:
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..color = AppColors.ink.withValues(alpha: 0.78);
        for (var row = 0; row < 4; row++) {
          final path = Path();
          final y = size.height * (row + 0.5) / 4;
          path.moveTo(0, y);
          for (var x = 0.0; x <= w; x += w / 16) {
            path.lineTo(x, y + math.sin(x / w * math.pi * 3) * w * 0.05);
          }
          canvas.drawPath(path, stroke);
        }
      case AvatarPattern.triangles:
        const cells = 4;
        final cell = w / cells;
        for (var y = 0; y < cells; y++) {
          for (var x = 0; x < cells; x++) {
            if (rng.nextBool()) continue;
            final path = Path()
              ..moveTo(x * cell, (y + 1) * cell)
              ..lineTo((x + 0.5) * cell, y * cell)
              ..lineTo((x + 1) * cell, (y + 1) * cell)
              ..close();
            canvas.drawPath(path, ink);
          }
        }
      case AvatarPattern.rings:
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.08
          ..color = AppColors.ink.withValues(alpha: 0.78);
        final centre = rect.center;
        for (var i = 1; i <= 3; i++) {
          canvas.drawCircle(centre, w * 0.14 * i, stroke);
        }
      case AvatarPattern.checks:
        const cells = 4;
        final cell = w / cells;
        for (var y = 0; y < cells; y++) {
          for (var x = 0; x < cells; x++) {
            if ((x + y).isOdd) continue;
            canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), ink);
          }
        }
      case AvatarPattern.sparkles:
        for (var i = 0; i < 7; i++) {
          final c = Offset(
            rng.nextDouble() * w,
            rng.nextDouble() * size.height,
          );
          final r = w * (0.05 + rng.nextDouble() * 0.07);
          final path = Path()
            ..moveTo(c.dx, c.dy - r)
            ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
            ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
            ..close();
          canvas.drawPath(path, ink);
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pattern != pattern || old.seed != seed || old.ground != ground;
}
