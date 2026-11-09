import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Hold something to look at it, without going there.
///
/// Floats in the middle of the screen over a blurred page, the way a
/// hard press does on iOS — not a sheet from the bottom. A sheet is
/// somewhere you have arrived; this is a glance you are still holding,
/// and it goes away when you let it.
///
/// Scales up from slightly small rather than sliding, so it reads as
/// the thing under your finger growing rather than a new page arriving.
/// [T] is what the panel can hand back, for the cases where a peek is
/// also a choice. Most callers only look, and leave it as void.
Future<T?> showFloatingPeek<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
  String? openLabel,
  VoidCallback? onOpen,
}) {
  HapticFeedback.mediumImpact();

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close $title',
    barrierColor: AppColors.ink.withValues(alpha: 0.28),
    transitionDuration: AppMotion.sheet,
    pageBuilder: (_, _, _) => _FloatingPeek(
      title: title,
      subtitle: subtitle,
      openLabel: openLabel,
      onOpen: onOpen,
      child: child,
    ),
    transitionBuilder: (context, animation, _, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.arriving,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          // From 92%, not from nothing: a panel that starts at zero
          // reads as a pop, and this is meant to read as a lift.
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FloatingPeek extends StatelessWidget {
  const _FloatingPeek({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.openLabel,
    required this.onOpen,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final String? openLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final media = MediaQuery.of(context);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The page behind goes soft, so the panel is plainly in front
          // of it rather than another card among the ones it covers.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppLayout.gutter),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 380,
                  maxHeight: media.size.height * 0.7,
                ),
                child: BrutCard(
                  shadow: AppShadows.lg,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: AppText.cardTitle),
                                if (subtitle case final s?) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    s,
                                    style: AppText.caption.copyWith(
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          BrutIconButton(
                            icon: Icons.close,
                            label: 'Close $title',
                            size: 32,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Flexible(child: SingleChildScrollView(child: child)),
                      if (onOpen != null) ...[
                        const SizedBox(height: 14),
                        BrutButton(
                          label: openLabel ?? 'Open',
                          icon: Icons.arrow_forward,
                          onPressed: () {
                            Navigator.of(context).maybePop();
                            onOpen!();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
