import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/admin_service.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/roster_import.dart';

/// A roster arrives as a spreadsheet, and the route for it existed on
/// the server with nothing in the app calling it.
///
/// The server checks the whole workbook before inserting any of it, so a
/// refusal names every bad row. Flattening that to one sentence throws
/// away the part worth showing.
void main() {
  AdminService serviceReturning(Object body, {int status = 200}) {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      ),
    );
    return AdminService(ApiClient(httpClient: client));
  }

  List<int> workbook([int size = 2048]) => List.filled(size, 0);

  group('what the server will take', () {
    test('an .xlsx workbook', () {
      expect(RosterWorkbook.problemWith('roster.xlsx', 2048), isNull);
      expect(RosterWorkbook.problemWith('ROSTER.XLSX', 2048), isNull);
    });

    test('and nothing else, however spreadsheet-like', () {
      // The server reads it with openpyxl, so .xls and .csv are out.
      expect(RosterWorkbook.problemWith('roster.xls', 2048), contains('.xlsx'));
      expect(RosterWorkbook.problemWith('roster.csv', 2048), contains('.xlsx'));
      expect(RosterWorkbook.problemWith('roster', 2048), contains('.xlsx'));
    });

    test('five megabytes is the line', () {
      expect(RosterWorkbook.problemWith('a.xlsx', 5 * 1024 * 1024), isNull);
      expect(
        RosterWorkbook.problemWith('a.xlsx', 5 * 1024 * 1024 + 1),
        contains('5 MB'),
      );
    });

    test('an empty file is caught', () {
      expect(RosterWorkbook.problemWith('a.xlsx', 0), contains('empty'));
    });

    test('it names the six columns the server looks for', () {
      expect(RosterWorkbook.headers, [
        'Department',
        'Organization Full Name',
        'Full Name',
        'Email',
        'Role',
        'Position',
      ]);
    });
  });

  group('uploading', () {
    test('a refused file never leaves the phone', () async {
      final service = serviceReturning(const {});

      expect(
        () => service.importRoster(bytes: workbook(), filename: 'roster.csv'),
        throwsArgumentError,
      );
    });

    test('a workbook that went on reports who it added', () async {
      final service = serviceReturning({
        'filename': 'roster.xlsx',
        'inserted_count': 2,
        'members': [
          {'id': 'a', 'email': 'one@lcup.edu.ph'},
          {'id': 'b', 'email': 'two@lcup.edu.ph'},
        ],
      });

      final result = await service.importRoster(
        bytes: workbook(),
        filename: 'roster.xlsx',
      );

      expect(result.insertedCount, 2);
      expect(result.emails, ['one@lcup.edu.ph', 'two@lcup.edu.ph']);
    });
  });

  group('a workbook the server refused', () {
    test('comes back with every bad row, not a count', () async {
      final service = serviceReturning({
        'detail': {
          'code': 'roster_import_invalid',
          'errors': [
            {'row': 4, 'column': 'Email', 'message': 'Not an address'},
            {'row': 9, 'column': 'Role', 'message': 'Unknown role'},
          ],
        },
      }, status: 422);

      await expectLater(
        service.importRoster(bytes: workbook(), filename: 'roster.xlsx'),
        throwsA(
          isA<RosterImportRejected>().having(
            (e) => e.errors.map((r) => r.row),
            'rows',
            [4, 9],
          ),
        ),
      );
    });

    test('and each row says which column and why', () async {
      final service = serviceReturning({
        'detail': {
          'code': 'roster_import_invalid',
          'errors': [
            {'row': 4, 'column': 'Email', 'message': 'Not an address'},
          ],
        },
      }, status: 422);

      try {
        await service.importRoster(bytes: workbook(), filename: 'roster.xlsx');
        fail('should have been refused');
      } on RosterImportRejected catch (rejected) {
        final only = rejected.errors.single;
        expect(only.row, 4);
        expect(only.column, 'Email');
        expect(only.message, 'Not an address');
        expect(only.toString(), contains('Row 4'));
      }
    });

    test('an ordinary failure stays an ordinary failure', () async {
      // A 403 is not a bad workbook, and must not be read as one.
      final service = serviceReturning(
        {'detail': 'Administrators only'},
        status: 403,
      );

      await expectLater(
        service.importRoster(bytes: workbook(), filename: 'roster.xlsx'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
