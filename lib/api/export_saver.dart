import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'api_client.dart';

/// Hands a downloaded export to the platform's share sheet, from which the
/// user can save it, mail it, or open it in a viewer.
///
/// Built on `XFile.fromData` rather than writing to disk: there is no file
/// system on web, and a temporary file left behind on mobile is one more
/// thing to clean up. The bytes are already in memory from the download.
///
/// Printing is the same path — a PDF opened in a viewer prints from there,
/// and the HTML export is print-ready by design, which is why there is no
/// separate print button pretending to drive a printer directly.
abstract final class ExportSaver {
  /// Offers [file] to the share sheet.
  ///
  /// Returns null when the sheet was shown, or a message when it could not
  /// be. A dismissed sheet is not an error — the user changed their mind —
  /// so that also returns null.
  static Future<String?> share(
    DownloadedFile file, {
    String? subject,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          subject: subject ?? file.filename,
          files: [
            XFile.fromData(
              Uint8List.fromList(file.bytes),
              mimeType: _bareMimeType(file.contentType),
              // Without this the shared file arrives unnamed on some
              // platforms, which makes a PDF hard to identify later.
              name: file.filename,
            ),
          ],
          fileNameOverrides: [file.filename],
        ),
      );

      return switch (result.status) {
        ShareResultStatus.unavailable =>
          'Sharing is not available on this device.',
        _ => null,
      };
    } catch (error) {
      return 'Could not open the share sheet: $error';
    }
  }

  /// `application/pdf` from `application/pdf; charset=utf-8` — the share
  /// sheet wants the type alone, not the whole header.
  static String _bareMimeType(String contentType) {
    final semicolon = contentType.indexOf(';');
    final bare =
        (semicolon < 0 ? contentType : contentType.substring(0, semicolon))
            .trim();
    return bare.isEmpty ? 'application/octet-stream' : bare;
  }
}
