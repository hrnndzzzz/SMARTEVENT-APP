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
    return BrutScreen(
      header: BrutHeader(
        eyebrow: '${format.label} · ${describeSize(file.sizeBytes)}',
        title: file.filename,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      scrollable: false,
      footer: BrutFooter(
        child: _ShareButton(file: file, subject: subject),
      ),
      child: switch (format) {
        ExportFormat.html => _HtmlView(file: file),
        ExportFormat.csv => _CsvTable(file: file),
        ExportFormat.pdf => _FileSummary(file: file),
      },
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

/// One table in an exported CSV: its heading, column names and rows. The
/// lines at the top of the file (title, what it covers) come back as a
/// section with only [lines].
class CsvSection {
  const CsvSection({
    this.heading,
    this.lines = const [],
    this.header = const [],
    this.rows = const [],
  });

  final String? heading;
  final List<String> lines;
  final List<String> header;
  final List<List<String>> rows;

  bool get isTable => header.isNotEmpty;

  /// A small CSV reader: quoted fields, doubled quotes inside them, and
  /// newlines that only end a row when they fall outside quotes. Blank
  /// lines come back as empty rows: they are where one table ends.
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
    return [
      for (final r in rows)
        if (r.any((c) => c.trim().isNotEmpty)) r else const <String>[],
    ];
  }

  /// The file split at its blank lines. In each part, a lone one-cell row
  /// is the heading and the row after it the column names; a part made
  /// only of one-cell rows is text, such as the title block.
  static List<CsvSection> split(String input) {
    final rows = parse(input.startsWith('\ufeff') ? input.substring(1) : input);
    final parts = <List<List<String>>>[[]];
    for (final row in rows) {
      row.isEmpty ? parts.add([]) : parts.last.add(row);
    }
    final sections = <CsvSection>[];
    for (final part in parts.where((p) => p.isNotEmpty)) {
      bool single(List<String> r) =>
          r.length == 1 || r.skip(1).every((c) => c.isEmpty);
      if (part.every(single)) {
        sections.add(CsvSection(lines: [for (final r in part) r.first]));
      } else if (single(part.first) && part.length > 1) {
        sections.add(
          CsvSection(
            heading: part.first.first,
            header: part[1],
            rows: part.skip(2).toList(),
          ),
        );
      } else {
        sections.add(CsvSection(header: part.first, rows: part.skip(1).toList()));
      }
    }
    return sections;
  }
}

/// The CSV as its tables, one after another, each with its own heading
/// and column names. It used to be read as one table under the title row,
/// so only the first column of anything showed.
class _CsvTable extends StatelessWidget {
  const _CsvTable({required this.file});

  final DownloadedFile file;

  @override
  Widget build(BuildContext context) {
    final sections = CsvSection.split(
      utf8.decode(file.bytes, allowMalformed: true),
    );

    if (sections.isEmpty) {
      return const Center(
        child: BrutEmptyState(
          title: 'The file is empty',
          hint: 'The export came back with no rows in it.',
          icon: Icons.table_chart_outlined,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in sections) ...[
          if (section.isTable) ...[
            if (section.heading case final heading?) ...[
              BrutSectionTitle(heading),
              const SizedBox(height: 8),
            ],
            _CsvGrid(section: section),
          ] else
            for (final (i, line) in section.lines.indexed)
              Text(line, style: i == 0 ? AppText.cardTitle : AppText.caption),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

/// One table, scrolling sideways when it is wider than the phone.
class _CsvGrid extends StatelessWidget {
  const _CsvGrid({required this.section});

  final CsvSection section;

  @override
  Widget build(BuildContext context) {
    final header = section.header;
    // Amounts read in a column, so they line up on the right.
    final money = {
      for (var c = 0; c < header.length; c++)
        if (header[c].contains('(PHP)')) c,
    };
    Widget cell(String text, int c, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: money.contains(c)
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: head
            ? MonoLabel(text)
            : Text(text, style: AppText.body.copyWith(fontSize: 12.5)),
      ),
    );

    return SingleChildScrollView(
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
                for (var c = 0; c < header.length; c++)
                  cell(header[c], c, head: true),
              ],
            ),
            for (final r in section.rows)
              TableRow(
                children: [
                  for (var c = 0; c < header.length; c++)
                    cell(c < r.length ? r[c] : '', c),
                ],
              ),
          ],
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
