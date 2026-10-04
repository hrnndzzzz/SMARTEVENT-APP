import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../api/export_saver.dart';
import '../api/models/reports.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Look at the file before sending it anywhere.
///
/// Sharing used to be the only thing that happened after an export, which
/// meant the first time anyone saw a report was in whatever app they sent
/// it to. The HTML export renders here, the CSV becomes a table, and the
/// PDF — which needs a renderer this app does not carry — is described
/// honestly rather than shown as a blank page.
///
/// Nothing is sent until Share is pressed. Backing out sends nothing.
class ExportPreviewScreen extends StatelessWidget {
  const ExportPreviewScreen({
    super.key,
    required this.file,
    required this.format,
    required this.subject,
  });

  final DownloadedFile file;
  final ExportFormat format;

  /// What the share sheet calls it.
  final String subject;

  static String describeSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              eyebrow: '${format.label} · ${describeSize(file.sizeBytes)}',
              title: file.filename,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: switch (format) {
                ExportFormat.html => _HtmlView(file: file),
                ExportFormat.csv => _CsvTable(file: file),
                ExportFormat.pdf => _FileSummary(file: file),
              },
            ),
            BrutFooter(
              child: _ShareButton(file: file, subject: subject),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareButton extends StatefulWidget {
  const _ShareButton({required this.file, required this.subject});

  final DownloadedFile file;
  final String subject;

  @override
  State<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<_ShareButton> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    final problem = await ExportSaver.share(
      widget.file,
      subject: widget.subject,
    );

    if (!mounted) return;
    setState(() => _sharing = false);

    if (problem != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$problem The file itself is fine '
            '(${widget.file.filename}, '
            '${ExportPreviewScreen.describeSize(widget.file.sizeBytes)}).',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrutButton(
      label: 'Share',
      icon: Icons.ios_share,
      size: BrutSize.large,
      busy: _sharing,
      busyLabel: 'Opening…',
      onPressed: _share,
    );
  }
}

/// The print-ready HTML, rendered.
///
/// Loaded from the bytes rather than from a URL, so it never leaves the
/// device and never asks the backend for anything a second time.
/// JavaScript is off: this is a report, and nothing in it should run.
class _HtmlView extends StatefulWidget {
  const _HtmlView({required this.file});

  final DownloadedFile file;

  @override
  State<_HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<_HtmlView> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setBackgroundColor(Colors.white)
    ..loadHtmlString(utf8.decode(widget.file.bytes, allowMalformed: true));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // White regardless of theme: the page is a document, and it is
          // the same document that comes out of the printer.
          color: Colors.white,
          borderRadius: AppRadius.cardAll,
          border: context.borderAll,
          boxShadow: context.shadows(AppShadows.base),
        ),
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}

/// The CSV as a table, with the header row kept in place.
class _CsvTable extends StatelessWidget {
  const _CsvTable({required this.file});

  final DownloadedFile file;

  /// A small CSV reader: quoted fields, doubled quotes inside them, and
  /// newlines that only end a row when they fall outside quotes.
  static List<List<String>> parse(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    // A trailing newline leaves one empty row behind.
    return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = parse(utf8.decode(file.bytes, allowMalformed: true));

    if (rows.isEmpty) {
      return const Center(
        child: BrutEmptyState(
          title: 'The file is empty',
          hint: 'The export came back with no rows in it.',
          icon: Icons.table_chart_outlined,
        ),
      );
    }

    final header = rows.first;
    final body = rows.skip(1).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: BrutCard(
          padding: EdgeInsets.zero,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: context.palette.line,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.card - AppBorders.width),
                  ),
                ),
                children: [
                  for (final cell in header)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: MonoLabel(cell),
                    ),
                ],
              ),
              for (final r in body)
                TableRow(
                  children: [
                    for (var c = 0; c < header.length; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          c < r.length ? r[c] : '',
                          style: AppText.body.copyWith(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything the app can honestly say about a file it cannot render.
class _FileSummary extends StatelessWidget {
  const _FileSummary({required this.file});

  final DownloadedFile file;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrutSectionTitle('Ready to share'),
                const SizedBox(height: 12),
                BrutDetailRow('File', file.filename),
                const SizedBox(height: 8),
                BrutDetailRow(
                  'Size',
                  ExportPreviewScreen.describeSize(file.sizeBytes),
                  mono: true,
                ),
                const SizedBox(height: 8),
                BrutDetailRow('Type', file.contentType),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const BrutInlineMessage(
            tone: BrutTone.neutral,
            icon: Icons.picture_as_pdf_outlined,
            text:
                'The app has no PDF renderer, so this one cannot be shown '
                'here. Share it to open it in a reader — or export the '
                'print-ready HTML instead, which does display.',
          ),
        ],
      ),
    );
  }
}
