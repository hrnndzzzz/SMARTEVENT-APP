import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// What the camera screen came back with.
sealed class CaptureResult {
  const CaptureResult();
}

/// A photo, cropped to the guide.
class CapturedReceipt extends CaptureResult {
  const CapturedReceipt({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// The person wants a photo they already have. The camera cannot reframe
/// one of those, so it hands the job back rather than pretending to.
class GalleryRequested extends CaptureResult {
  const GalleryRequested();
}

/// The shape of the thing being photographed.
///
/// A thermal receipt and a printed invoice are different enough that one
/// guide cannot serve both: a receipt is a long narrow strip, an invoice
/// is a sheet of paper. The guide is what the photo is cropped to, so
/// getting it right is what keeps OCR from reading the table underneath.
enum PaperShape {
  receipt(0.42, 'Receipt', 'RECEIPT · NARROW STRIP'),
  document(210 / 297, 'Document', 'DOCUMENT · A4');

  const PaperShape(this.ratio, this.label, this.caption);

  /// Width divided by height.
  final double ratio;
  final String label;
  final String caption;
}

/// Photograph a receipt, cropped to the frame.
///
/// Always dark, whatever the app's theme: a bright screen behind a camera
/// is a light source pointed at the paper, and the viewfinder is easier
/// to judge against black.
///
/// It reports only what it actually knows. The light reading is measured
/// from the frames; there is no edge detection here, so the screen never
/// claims to have found the paper's boundaries — the frame is a guide for
/// the person holding the phone, not a promise from the app.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  static const _backdrop = Color(0xFF141414);
  static const _wellFill = Color(0xFF2B2B2B);

  /// How much of the viewfinder the guide may occupy.
  ///
  /// Nearly all of it. The guide and the viewfinder were two frames an
  /// inch apart, which read as a mistake rather than as a margin — so
  /// the corners now sit just inside the well's own edge and the shape
  /// toggle is what changes, not the size.
  static const _guideFraction = 0.96;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];

  /// Null until the first frame arrives. Until then the preview is not
  /// shown at all, so there is never a blank player on screen.
  bool _streaming = false;

  bool _failed = false;
  String? _failure;

  /// Receipts are what this screen is for. The choice between a strip
  /// and an A4 sheet was a control on the viewfinder that nothing ever
  /// set to anything but the strip, and a wrong guess crops the photo.
  static const PaperShape _shape = PaperShape.receipt;
  bool _torchOn = false;
  bool _torchBusy = false;
  bool _busy = false;
  bool _flashOverlay = false;

  /// 0–1, averaged from the luminance plane. Null until measured.
  double? _light;
  DateTime _lastLightRead = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _startupWatchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: _backdrop,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _backdrop,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startupWatchdog?.cancel();
    _teardown();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS takes the camera away when the app goes back; holding the
    // controller through it leaves a dead preview on return.
    if (state == AppLifecycleState.inactive) {
      _teardown();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start();
    }
  }

  Future<void> _teardown() async {
    final controller = _controller;
    _controller = null;
    _streaming = false;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Already stopped, or the camera went away with the app.
    }
    await controller.dispose();
  }

  /// The rear lens with the flash, which is the main one rather than the
  /// ultra-wide a phone often offers first.
  CameraDescription? _preferredCamera() {
    final back = _cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();
    if (back.isEmpty) return _cameras.isEmpty ? null : _cameras.first;
    return back.first;
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      final camera = _preferredCamera();
      if (camera == null) {
        _fail('No camera on this device.');
        return;
      }
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;

      // If frames never arrive the preview would sit black forever, so
      // the gallery route is offered instead after a bounded wait.
      _startupWatchdog = Timer(const Duration(seconds: 8), () {
        if (mounted && !_streaming) {
          _fail('The camera did not start.');
        }
      });

      await controller.startImageStream(_onFrame);
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      _fail(switch (e.code) {
        'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
          'Camera access is off for SmartEvent.',
        _ => 'The camera could not be opened.',
      });
    } catch (_) {
      _fail('The camera could not be opened.');
    }
  }

  void _fail(String why) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _failure = why;
    });
  }

  /// Brightness, measured rather than guessed.
  ///
  /// YUV's first plane is luminance already, so an average over a sparse
  /// sample of it is the reading — no colour conversion, and cheap enough
  /// to run on the stream.
  void _onFrame(CameraImage image) {
    if (!_streaming && mounted) {
      _startupWatchdog?.cancel();
      setState(() => _streaming = true);
    }
    final now = DateTime.now();
    if (now.difference(_lastLightRead) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastLightRead = now;

    final plane = image.planes.first.bytes;
    if (plane.isEmpty) return;
    // ~576 samples, the same order of magnitude as a 24x24 thumbnail.
    final step = math.max(1, plane.length ~/ 576);
    var total = 0;
    var count = 0;
    for (var i = 0; i < plane.length; i += step) {
      total += plane[i];
      count++;
    }
    final value = (total / count) / 255.0;
    if (mounted && (_light == null || (value - _light!).abs() > 0.02)) {
      setState(() => _light = value);
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || _torchBusy) return;
    setState(() => _torchBusy = true);
    try {
      final next = _torchOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(next);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } on CameraException {
      if (mounted) {
        setState(() => _torchOn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This phone will not let the app use the flash. '
              'Move closer to a light instead.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _torchBusy = false);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy || !_streaming) return;
    setState(() {
      _busy = true;
      _flashOverlay = true;
    });
    try {
      // The stream and a still capture contend for the camera on some
      // devices, so the stream stands down for the shot.
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final cropped = await _cropToGuide(bytes, _shape.ratio);
      if (!mounted) return;
      Navigator.of(context).pop<CaptureResult>(
        CapturedReceipt(
          bytes: cropped,
          filename: 'receipt-${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _flashOverlay = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That photo could not be taken.')),
        );
      }
      if (_controller != null && !_controller!.value.isStreamingImages) {
        try {
          await _controller!.startImageStream(_onFrame);
        } catch (_) {
          // The preview is gone; the gallery route still works.
        }
      }
    } finally {
      if (mounted && _flashOverlay) {
        Future.delayed(const Duration(milliseconds: 260), () {
          if (mounted) setState(() => _flashOverlay = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(16.0, MediaQuery.paddingOf(context).bottom);
    final live = _streaming && _controller != null;

    return PopScope(
      onPopInvokedWithResult: (_, __) => _teardown(),
      child: Scaffold(
        backgroundColor: _backdrop,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                onBack: () {
                  _teardown();
                  Navigator.of(context).maybePop();
                },
              ),
              const _StepBars(current: 0, total: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _Viewfinder(
                    controller: live ? _controller : null,
                    shape: _shape,
                    guideFraction: _guideFraction,
                    light: _light,
                    failed: _failed,
                    flashOverlay: _flashOverlay,
                    wellFill: _wellFill,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(
                  _hint(live),
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(32, 12, 32, bottom),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Tile(
                      icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                      label: _torchBusy
                          ? 'Finding…'
                          : !live
                          ? 'Flash'
                          : _torchOn
                          ? 'Flash on'
                          : 'Flash off',
                      fill: _torchOn ? AppColors.orange : Colors.white,
                      enabled: live && !_torchBusy,
                      onTap: _toggleTorch,
                      semantic: _torchOn ? 'Flash on' : 'Flash off',
                    ),
                    _Shutter(enabled: live && !_busy, onTap: _capture),
                    _Tile(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      fill: Colors.white,
                      enabled: !_busy,
                      onTap: () {
                        _teardown();
                        Navigator.of(
                          context,
                        ).pop<CaptureResult>(const GalleryRequested());
                      },
                      semantic: 'Pick a photo instead',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hint(bool live) {
    if (_failed) {
      return '${_failure ?? 'Camera unavailable.'} '
          'Pick a photo from the gallery instead.';
    }
    if (!live) return 'Starting the camera…';
    if ((_light ?? 1) < 0.22) {
      return 'Low light. Turn on the flash, or move closer to a window.';
    }
    return 'Line the receipt up inside the frame and hold steady.';
  }
}

/// Crops to the guide and shrinks what comes out.
///
/// Runs off the UI thread: decoding a full-resolution JPEG takes long
/// enough to drop frames, and this happens behind the shutter flash.
Future<Uint8List> _cropToGuide(Uint8List bytes, double ratio) async {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    // The preview is cover-fitted, so the guide maps onto the same
    // fraction of the photo's shorter dimension.
    const fraction = 0.96;
    final guideW = math.min(
      decoded.width * fraction,
      decoded.height * fraction * ratio,
    );
    final guideH = guideW / ratio;
    final rect = img.copyCrop(
      decoded,
      x: ((decoded.width - guideW) / 2).round(),
      y: ((decoded.height - guideH) / 2).round(),
      width: guideW.round(),
      height: guideH.round(),
    );
    final sized = rect.height > 1400
        ? img.copyResize(rect, height: 1400)
        : rect;
    return img.encodeJpg(sized, quality: 85);
  });
}

/// Back, the step and what is being shot, and the shape toggle.
class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Semantics(
            label: 'Back',
            button: true,
            child: GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: AppRadius.controlAll,
                  border: Border.all(color: AppColors.ink, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x59FFFFFF), offset: Offset(2, 2)),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STEP 01 / 02 · CAPTURE',
                  style: AppText.monoLabel.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'New expense',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// How far along the scan is. Capture, then check and save.
class _StepBars extends StatelessWidget {
  const _StepBars({required this.current, required this.total});

  final int current;
  final int total;

  static const _names = ['Capture', 'Check and save'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Semantics(
                label: 'Step ${i + 1}: ${_names[i]}',
                selected: i == current,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == current ? AppColors.orange : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The camera, the guide over it, and the two readings.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.controller,
    required this.shape,
    required this.guideFraction,
    required this.light,
    required this.failed,
    required this.flashOverlay,
    required this.wellFill,
  });

  final CameraController? controller;
  final PaperShape shape;
  final double guideFraction;
  final double? light;
  final bool failed;
  final bool flashOverlay;
  final Color wellFill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.cardAll,
      child: Container(
        decoration: BoxDecoration(
          color: wellFill,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // The guide is the largest rectangle of this shape that fits
            // inside the allowed fraction of the well.
            var width = box.maxWidth * guideFraction;
            var height = width / shape.ratio;
            if (height > box.maxHeight * guideFraction) {
              height = box.maxHeight * guideFraction;
              width = height * shape.ratio;
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null)
                  // Cover rather than contain: letterboxing a preview
                  // wastes the part of the frame the guide sits in.
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width:
                          controller!.value.previewSize?.height ?? box.maxWidth,
                      height:
                          controller!.value.previewSize?.width ?? box.maxHeight,
                      child: CameraPreview(controller!),
                    ),
                  )
                else
                  Center(
                    child: Icon(
                      failed
                          ? Icons.no_photography_outlined
                          : Icons.photo_camera_outlined,
                      size: 44,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),

                // Everything outside the guide is dimmed, so the paper
                // area is the bright part of the screen.
                if (controller != null)
                  _GuideScrim(width: width, height: height),

                Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: CustomPaint(
                      painter: _GuidePainter(live: controller != null),
                    ),
                  ),
                ),

                // The caption sits under the guide rather than in it.
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: height + 36),
                    child: Text(
                      shape.caption,
                      style: AppText.monoLabel.copyWith(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: _Chip(
                          text: failed
                              ? 'Camera unavailable'
                              : controller == null
                              ? 'Starting camera…'
                              : 'Camera ready',
                          fill: failed
                              ? AppColors.coral
                              : controller == null
                              ? Colors.white
                              : AppColors.mint,
                          announce: true,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: _Chip(
                          text: light == null
                              ? '—'
                              : 'LIGHT ${(light! * 100).round()}%',
                          fill: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                if (flashOverlay) const ColoredBox(color: Color(0xCCFFFFFF)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Darkens everything but the guide.
class _GuideScrim extends StatelessWidget {
  const _GuideScrim({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScrimPainter(width: width, height: height),
      ),
    );
  }
}

/// Fills everything except the guide, in one path, so the guide stays at
/// full brightness without compositing tricks.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.width, required this.height});

  final double width;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: height,
    );
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(hole),
    );
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.width != width || old.height != height;
}

/// The frame: a closed outline, with thirds ruled faintly inside it.
///
/// Dashed while the camera is still coming up, solid once it is live.
/// Neither state claims the paper has been found — nothing here looks
/// for it, and the thirds are for squaring up by eye, not a detection.
class _GuidePainter extends CustomPainter {
  const _GuidePainter({required this.live});

  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: live ? 0.75 : 0.55);

    if (live) {
      canvas.drawRect(rect, outline);
    } else {
      _dashed(canvas, rect, outline);
    }

    // Thirds, faintly. They are for squaring the paper up against
    // something straight; at this weight they do not compete with the
    // receipt underneath.
    if (live) {
      final rule = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.18);

      for (var i = 1; i < 3; i++) {
        final x = size.width * i / 3;
        final y = size.height * i / 3;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), rule);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
      }
    }

    // A closed frame rather than four corner brackets. The brackets left
    // the long sides of a receipt unmarked, which is the edge that is
    // hardest to line up.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.orange.withValues(alpha: live ? 1.0 : 0.6);
    canvas.drawRect(rect.deflate(2), border);
  }

  void _dashed(Canvas canvas, Rect rect, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    for (final (from, to) in [
      (rect.topLeft, rect.topRight),
      (rect.topRight, rect.bottomRight),
      (rect.bottomRight, rect.bottomLeft),
      (rect.bottomLeft, rect.topLeft),
    ]) {
      final span = (to - from).distance;
      final unit = (to - from) / span;
      var walked = 0.0;
      while (walked < span) {
        final end = math.min(walked + dash, span);
        canvas.drawLine(from + unit * walked, from + unit * end, paint);
        walked = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.live != live;
}

/// A reading, in the corner of the viewfinder.
class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.fill, this.announce = false});

  final String text;
  final Color fill;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 2,
        style: AppText.monoLabel.copyWith(fontSize: 10, color: AppColors.ink),
      ),
    );
    return announce ? Semantics(liveRegion: true, child: chip) : chip;
  }
}

/// Flash and gallery. One shape, two jobs.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.fill,
    required this.enabled,
    required this.onTap,
    required this.semantic,
  });

  final IconData icon;
  final String label;
  final Color fill;
  final bool enabled;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantic,
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: enabled ? onTap : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: AppRadius.controlAll,
                  border: Border.all(color: AppColors.ink, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40FFFFFF), offset: Offset(2, 2)),
                  ],
                ),
                child: Icon(icon, size: 22, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label.toUpperCase(),
              style: AppText.monoLabel.copyWith(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shutter. It presses down onto its own shadow.
class _Shutter extends StatefulWidget {
  const _Shutter({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down && widget.enabled;
    return Semantics(
      label: 'Capture receipt',
      button: true,
      enabled: widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.6,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.press,
            curve: Curves.easeOut,
            width: 76,
            height: 76,
            alignment: Alignment.center,
            transform: Matrix4.translationValues(
              pressed ? 3 : 0,
              pressed ? 3 : 0,
              0,
            ),
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: pressed
                  ? const []
                  : const [
                      BoxShadow(color: Colors.white, offset: Offset(3, 3)),
                    ],
            ),
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ink, width: 2),
              ),
              child: const Icon(
                Icons.photo_camera,
                size: 28,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
