import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Tap the bell to see what the number counts.
///
/// A small window over the page rather than a screen of its own: an
/// inbox you have to navigate into, and back out of, is a lot of
/// ceremony for four lines of text you mostly want to dismiss.
///
/// The rule this is built around: **the number on the badge is the length
/// of the list in the window.** If they can disagree the window is worse
/// than nothing, so when the inbox has not been loaded yet it says so
/// rather than showing a shorter list than the badge promised.
///
/// Tap a row to mark it read. Tap anywhere else to close.
class NotificationPeek extends StatefulWidget {
  const NotificationPeek({super.key, required this.child, required this.onTap});

  /// The bell itself.
  final Widget child;

  /// What a plain tap does.
  final VoidCallback? onTap;

  @override
  State<NotificationPeek> createState() => _NotificationPeekState();
}

class _NotificationPeekState extends State<NotificationPeek> {
  OverlayEntry? _entry;
  final _anchor = GlobalKey();
  final _rowKeys = <GlobalKey>[];

  int? _highlighted;
  List<AppNotice> _rows = const [];

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  List<AppNotice> _unreadOf(AppState app) =>
      app.notices.where((n) => n.isUnread).toList();

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    _open();
  }

  void _open() {
    final app = context.read<AppState>();
    _rows = _unreadOf(app);
    // The badge counts what the server says; the list is what this device
    // has fetched. Fetch rather than show fewer than the badge promised.
    if (_rows.length != app.unreadNoticeCount) app.loadNotices();
    // Nothing to show and nothing on the way: say so rather than opening
    // an empty card that looks like a failure.
    if (app.unreadNoticeCount == 0 && _rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing new.')),
      );
      return;
    }

    _rowKeys
      ..clear()
      ..addAll(List.generate(_rows.length, (_) => GlobalKey()));
    _highlighted = null;

    HapticFeedback.mediumImpact();

    final overlay = Overlay.of(context);
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    final anchorRect = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;

    _entry = OverlayEntry(
      builder: (overlayContext) => _PeekLayer(
        anchor: anchorRect,
        rows: _rows,
        rowKeys: _rowKeys,
        highlighted: _highlighted,
        total: app.unreadNoticeCount,
        onDismiss: _close,
        onChoose: _choose,
      ),
    );
    overlay.insert(_entry!);
  }

  Future<void> _choose(int index) async {
    if (index < 0 || index >= _rows.length) return;
    final notice = _rows[index];
    _close();

    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().markNoticeRead(notice);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _highlighted = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _anchor,
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: widget.child,
    );
  }
}

/// The blurred scrim and the card, drawn over everything.
class _PeekLayer extends StatelessWidget {
  const _PeekLayer({
    required this.anchor,
    required this.rows,
    required this.rowKeys,
    required this.highlighted,
    required this.total,
    required this.onDismiss,
    required this.onChoose,
  });

  final Rect anchor;
  final List<AppNotice> rows;
  final List<GlobalKey> rowKeys;
  final int? highlighted;
  final int total;
  final VoidCallback onDismiss;
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Below the bell when there is room, above it otherwise, and always
    // inside the screen.
    const cardWidth = 300.0;
    final left = (anchor.center.dx - cardWidth / 2).clamp(
      12.0,
      size.width - cardWidth - 12,
    );
    final top = anchor.bottom + 12;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: reduceMotion
                  ? ImageFilter.blur()
                  : ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(
                color: context.palette.canvas.withValues(alpha: 0.55),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: cardWidth,
          child: BrutCard(
              shadow: AppShadows.lg,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MonoLabel('$total unread'),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    const Text('Loading…', style: AppText.caption)
                  else ...[
                    for (var i = 0; i < rows.length; i++) ...[
                      GestureDetector(
                        key: rowKeys[i],
                        onTap: () => onChoose(i),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: highlighted == i
                              ? context.palette.sunTint
                              : Colors.transparent,
                          borderRadius: AppRadius.controlAll,
                          border: Border.fromBorderSide(
                            highlighted == i ? context.side : BorderSide.none,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].title,
                              style: AppText.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              rows[i].body,
                              style: AppText.caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        ),
                      ),
                      if (i != rows.length - 1) const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 10),
                    const MonoLabel('Tap one to mark it read'),
                  ],
                ],
              ),
            ),
        ),
      ],
    );
  }
}
