import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// A file held in storage, shown.
///
/// The reference on a record is not always loadable as-is — once the
/// buckets are private it has to be exchanged for a signed URL — so this
/// asks AppState to resolve it first and only then loads it. Tapping
/// opens it full-screen, which is the point: a receipt is read by
/// looking at it.
class StoredImage extends StatefulWidget {
  const StoredImage({
    super.key,
    required this.reference,
    this.height = 220,
    this.label = 'Receipt photo',
  });

  final String reference;
  final double height;
  final String label;

  @override
  State<StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends State<StoredImage> {
  late Future<String> _url = context.read<AppState>().resolveFile(
    widget.reference,
  );

  @override
  void didUpdateWidget(StoredImage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) {
      _url = context.read<AppState>().resolveFile(widget.reference);
    }
  }

  void _open(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreen(url: url, label: widget.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        return BrutSurface(
          onTap: url == null ? null : () => _open(url),
          semanticLabel: widget.label,
          padding: EdgeInsets.zero,
          radius: AppRadius.cardAll,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              AppRadius.card - AppBorders.width,
            ),
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: url == null
                  ? Center(child: BrutSpinner())
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : Center(child: BrutSpinner()),
                      // A stored file that will not load is worth saying
                      // plainly: the record is fine, the image is not.
                      errorBuilder: (context, _, __) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 28,
                              color: context.palette.muted,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The image could not be loaded.',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// The photo on its own, against black, pinchable.
class _FullScreen extends StatelessWidget {
  const _FullScreen({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          label,
          style: AppText.cardTitle.copyWith(color: Colors.white),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, _, __) => const Text(
              'The image could not be loaded.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
