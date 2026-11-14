import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/brut.dart';

/// Somewhere to draw the one electronic signature in the whole form.
///
/// Points leave here normalised to the box, 0 to 1 on both axes, because
/// that is what the server stores and what lets the same signature be
/// drawn back at any size. Nothing here knows about pixels once a stroke
/// is finished.
///
/// A finger is not a pen: strokes are kept as they arrive rather than
/// smoothed, so what is stored is what was drawn.
class SapSignaturePad extends StatefulWidget {
  const SapSignaturePad({
    super.key,
    required this.onChanged,
    this.enabled = true,
    this.height = 200,
  });

  /// Called with the whole drawing whenever a stroke ends.
  final ValueChanged<SapSignature> onChanged;
  final bool enabled;
  final double height;

  @override
  State<SapSignaturePad> createState() => _SapSignaturePadState();
}

class _SapSignaturePadState extends State<SapSignaturePad> {
  final List<List<SapSignaturePoint>> _strokes = [];
  List<SapSignaturePoint> _current = [];

  Size _size = Size.zero;

  /// Clamped, because a finger that leaves the box mid-stroke would
  /// otherwise send a coordinate the server refuses — and the signer
  /// would be told to draw it again with no idea why.
  SapSignaturePoint _normalise(Offset local) {
    final w = _size.width == 0 ? 1 : _size.width;
    final h = _size.height == 0 ? 1 : _size.height;
    return SapSignaturePoint(
      (local.dx / w).clamp(0.0, 1.0),
      (local.dy / h).clamp(0.0, 1.0),
    );
  }

  void _start(Offset local) {
    if (!widget.enabled) return;
    setState(() => _current = [_normalise(local)]);
  }

  void _extend(Offset local) {
    if (!widget.enabled || _current.isEmpty) return;
    setState(() => _current = [..._current, _normalise(local)]);
  }

  void _end() {
    if (_current.isEmpty) return;
    setState(() {
      _strokes.add(_current);
      _current = [];
    });
    widget.onChanged(SapSignature(List.of(_strokes)));
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
    widget.onChanged(SapSignature(List.of(_strokes)));
  }

  void _clear() {
    if (_strokes.isEmpty && _current.isEmpty) return;
    setState(() {
      _strokes.clear();
      _current = [];
    });
    widget.onChanged(const SapSignature([]));
  }

  @override
  Widget build(BuildContext context) {
    final drawing = SapSignature([
      ..._strokes,
      if (_current.isNotEmpty) _current,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            _size = Size(constraints.maxWidth, widget.height);
            return RawGestureDetector(
              gestures: {
                _PadPanRecognizer:
                    GestureRecognizerFactoryWithHandlers<_PadPanRecognizer>(
                      _PadPanRecognizer.new,
                      (r) {
                        r.onStart = (d) => _start(d.localPosition);
                        r.onUpdate = (d) => _extend(d.localPosition);
                        r.onEnd = (_) {
                          _end();
                        };
                        r.onCancel = _end;
                      },
                    ),
              },
              child: BrutSurface(
                fill: context.palette.surface,
                radius: AppRadius.controlAll,
                shadow: AppShadows.none,
                height: widget.height,
                child: CustomPaint(
                  painter: _SignaturePainter(
                    strokes: drawing.strokes,
                    colour: context.palette.ink,
                  ),
                  child: _strokes.isEmpty && _current.isEmpty
                      ? Center(
                          child: Text(
                            widget.enabled ? 'Sign here' : 'Signing is closed',
                            style: AppText.caption,
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BrutButton(
                label: 'Undo stroke',
                icon: Icons.undo,
                tone: BrutTone.neutral,
                onPressed: widget.enabled && _strokes.isNotEmpty ? _undo : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BrutButton(
                label: 'Clear',
                icon: Icons.delete_outline,
                tone: BrutTone.neutral,
                onPressed:
                    widget.enabled &&
                        (_strokes.isNotEmpty || _current.isNotEmpty)
                    ? _clear
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A pan that does not give way to the scroll view it sits in.
///
/// The pad lives inside a scrollable page. A vertical stroke — the stem
/// of a letter, most of a signature — is a vertical drag, and the
/// scrollable wins that contest: the page scrolls and the stroke is
/// never drawn. Refusing to be rejected keeps the gesture here, which is
/// what a drawing surface wants. Scrolling past the pad is done from
/// either side of it.
class _PadPanRecognizer extends PanGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, required this.colour});

  final List<List<SapSignaturePoint>> strokes;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = colour
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      // A tap with no travel is a dot, and a path with one point draws
      // nothing at all.
      if (stroke.length == 1) {
        final p = stroke.single;
        canvas.drawCircle(
          Offset(p.x * size.width, p.y * size.height),
          1.25,
          brush..style = PaintingStyle.fill,
        );
        brush.style = PaintingStyle.stroke;
        continue;
      }

      final path = Path()
        ..moveTo(stroke.first.x * size.width, stroke.first.y * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      canvas.drawPath(path, brush);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.strokes != strokes || old.colour != colour;
}
