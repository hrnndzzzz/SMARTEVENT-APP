import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/reports.dart';
import 'package:smartevent/screens/export_preview_screen.dart';
import 'package:smartevent/theme/app_theme.dart';

/// An exported CSV holds several tables. The preview used to read the
/// whole file as one table under the title row, so it showed one column.
void main() {
  // The shape the backend writes: BOM, title block, then headed tables.
  const csv =
      '\ufeffSMARTEVENT Financial Report\r\n'
      'School year · 2026-2027\r\n'
      'Generated 16 Nov 2026\r\n'
      '\r\n'
      'Summary\r\n'
      'Figure,Value\r\n'
      'Income (PHP),19500.00\r\n'
      'Budget used,90%\r\n'
      '\r\n'
      '"Events (budget and spent to date cover the whole event, not only this period)"\r\n'
      'Event,Status,Allocated (PHP),Spent to date (PHP)\r\n'
      '"CITE Week: Opening, Day 1",Approved,11000.00,11950.00\r\n'
      'Capstone,Pending adviser,8000.00,0.00\r\n'
      '\r\n'
      'Ledger\r\n'
      'Date,Type,Amount (PHP)\r\n'
      '2026-09-19,Expense,-2450.00\r\n';

  test('splits at blank lines into the title block and each table', () {
    final sections = CsvSection.split(csv);
    expect(sections, hasLength(4));

    expect(sections[0].isTable, isFalse);
    expect(sections[0].lines, [
      'SMARTEVENT Financial Report',
      'School year · 2026-2027',
      'Generated 16 Nov 2026',
    ]);

    expect(sections[1].heading, 'Summary');
    expect(sections[1].header, ['Figure', 'Value']);
    expect(sections[1].rows, hasLength(2));

    final events = sections[2];
    expect(events.heading, startsWith('Events (budget'));
    expect(events.header, hasLength(4));
    // A quoted comma stays inside its cell.
    expect(events.rows.first.first, 'CITE Week: Opening, Day 1');

    expect(sections[3].heading, 'Ledger');
    expect(sections[3].rows.single.last, '-2450.00');
  });

  test('a plain one-table CSV still reads as one table', () {
    final sections = CsvSection.split('Name,Amount (PHP)\nA,1.00\nB,2.00\n');
    expect(sections.single.isTable, isTrue);
    expect(sections.single.heading, isNull);
    expect(sections.single.header, ['Name', 'Amount (PHP)']);
    expect(sections.single.rows, hasLength(2));
  });

  test('an empty file has nothing to show', () {
    expect(CsvSection.split(''), isEmpty);
    expect(CsvSection.split('\r\n\r\n'), isEmpty);
  });

  testWidgets('the preview shows every table, with all its columns', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ExportPreviewScreen(
          file: DownloadedFile(
            bytes: utf8.encode(csv),
            contentType: 'text/csv',
            filename: 'smartevent-financial-report.csv',
          ),
          format: ExportFormat.csv,
          subject: 'SMARTEVENT financial report',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('SMARTEVENT Financial Report'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('ALLOCATED (PHP)'), findsOneWidget);
    expect(find.text('11950.00'), findsOneWidget);
  });
}
