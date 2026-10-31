import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';

/// Supporting files. The one that carries a rule is the ROC/COC: an
/// off-campus proposal cannot be submitted without one on the revision
/// being sent.
///
/// Type and size are checked before sending. A refusal otherwise costs
/// the whole transfer first, which on a phone is a slow way to find out
/// a file was the wrong sort.
void main() {
  late List<http.BaseRequest> sent;

  SapService serviceReturning(Object body, {int status = 200}) {
    sent = [];
    final client = MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return SapService(ApiClient(httpClient: client));
  }

  // Exactly `SAPAttachmentOut` in smartevent-backend/app/schemas_sap.py.
  final row = {
    'id': 'a1',
    'category': 'roc_coc',
    'display_name': 'roc.pdf',
    'file_name': 'roc.pdf',
    'content_type': 'application/pdf',
    'sha256': 'a' * 64,
    'uploaded_at': '2026-10-27T08:00:00',
  };

  group('what the server will take', () {
    test('the three allowed types are allowed', () {
      expect(SapUploadLimits.contentTypeFor('roc.pdf'), 'application/pdf');
      expect(SapUploadLimits.contentTypeFor('scan.PNG'), 'image/png');
      expect(SapUploadLimits.contentTypeFor('photo.jpeg'), 'image/jpeg');
      expect(SapUploadLimits.contentTypeFor('photo.jpg'), 'image/jpeg');
    });

    test('anything else is refused by name', () {
      expect(SapUploadLimits.contentTypeFor('notes.docx'), isNull);
      expect(SapUploadLimits.contentTypeFor('noextension'), isNull);
      expect(SapUploadLimits.contentTypeFor('trailing.'), isNull);
      expect(
        SapUploadLimits.problemWith('notes.docx', 10),
        contains('PDF, PNG and JPEG'),
      );
    });

    test('ten megabytes is the line', () {
      expect(SapUploadLimits.problemWith('a.pdf', 10 * 1024 * 1024), isNull);
      expect(
        SapUploadLimits.problemWith('a.pdf', 10 * 1024 * 1024 + 1),
        contains('10 MB'),
      );
    });

    test('an empty file is caught', () {
      expect(SapUploadLimits.problemWith('a.pdf', 0), contains('empty'));
    });
  });

  group('uploading', () {
    test('the version and category ride as form fields', () async {
      // The server answers an upload with the whole proposal.
      final service = serviceReturning({
        'id': 'p1',
        'event_id': 'e1',
        'state': 'draft',
        'version': 4,
        'revision_no': 0,
        'attachments': [row],
      }, status: 201);

      final saved = await service.uploadAttachment(
        'e1',
        expectedVersion: 3,
        category: SapAttachmentCategory.rocCoc,
        bytes: List.filled(2048, 0),
        filename: 'roc.pdf',
      );

      final request = sent.single as http.Request;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/sap-proposal/attachments'));
      expect(
        request.body,
        matches(RegExp(r'name="expected_version"\r\n\r\n3\r\n')),
      );
      expect(request.body, matches(RegExp(r'name="category"\r\n\r\nroc_coc')));
      expect(saved.version, 4);
    });

    test('a file the server would refuse never leaves the phone', () async {
      final service = serviceReturning(row);

      expect(
        () => service.uploadAttachment(
          'e1',
          expectedVersion: 1,
          category: SapAttachmentCategory.rocCoc,
          bytes: List.filled(10, 0),
          filename: 'notes.docx',
        ),
        throwsArgumentError,
      );
      expect(sent, isEmpty);
    });
  });

  group('listing', () {
    test('a bare list is read', () async {
      final service = serviceReturning([row]);
      final files = await service.attachments('e1');

      expect(files, hasLength(1));
      expect(files.single.id, 'a1');
      expect(files.single.filename, 'roc.pdf');
    });

    test('a wrapped list is read too', () async {
      // The contract does not promise which shape, and assuming one is
      // how the collections came back empty the first time.
      final service = serviceReturning({
        'attachments': [row],
      });

      expect(await service.attachments('e1'), hasLength(1));
    });

    test('nothing attached is not an error', () async {
      final service = serviceReturning(<String, dynamic>{});
      expect(await service.attachments('e1'), isEmpty);
    });
  });

  test('every category the server keeps has a name here', () {
    for (final wire in ['apf', 'pcf', 'appendix', 'roc_coc', 'other']) {
      expect(SapAttachmentCategory.fromWire(wire), isNotNull, reason: wire);
    }
    expect(SapAttachmentCategory.values, hasLength(5));
  });
}
