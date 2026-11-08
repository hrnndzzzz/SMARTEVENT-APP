import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart' show ApiException;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// The server refuses a reference that names no stored file (422) or one it
/// cannot find (404): that is a record without a photo, not an error to read out.
bool _noStoredFile(Object? error) =>
    error is ApiException && (error.isValidationError || error.isNotFound);

/// 410: the server removed the photo after 30 days; its record remains.
bool _photoRemoved(Object? error) =>
    error is ApiException && error.statusCode == 410;

Widget _brokenImage(BuildContext context, String message) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(Icons.broken_image_outlined, size: 28, color: context.palette.muted),
    const SizedBox(height: 8),
    Text(message, style: AppText.caption, textAlign: TextAlign.center),
  ],
);

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
  late Future<DownloadedFile> _url = context.read<AppState>().downloadedFile(
    widget.reference,
  );

  @override
  void didUpdateWidget(StoredImage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) {
      _url = context.read<AppState>().downloadedFile(widget.reference);
    }
  }

  void _open(DownloadedFile url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreen(url: url, label: widget.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DownloadedFile>(
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
                  ? Center(
                      child: !snapshot.hasError
                          ? BrutSpinner()
                          : _noStoredFile(snapshot.error)
                          ? _brokenImage(
                              context,
                              'No ${widget.label.toLowerCase()} is stored.',
                            )
                          : _photoRemoved(snapshot.error)
                          ? _brokenImage(context, '${snapshot.error}')
                          : Text(
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                    )
                  : Image.memory(
                      Uint8List.fromList(url.bytes),
                      fit: BoxFit.cover,
                      // A stored file that will not load is worth saying
                      // plainly: the record is fine, the image is not.
                      errorBuilder: (context, _, __) => Center(
                        child: _brokenImage(
                          context,
                          'The image could not be loaded.',
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

  final DownloadedFile url;
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
          child: Image.memory(
            Uint8List.fromList(url.bytes),
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
