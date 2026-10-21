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

  final row = {
    'id': 'a1',
    'category': 'roc_coc',
    'filename': 'roc.pdf',
    'size_bytes': 2048,
    'revision_no': 1,
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
    test('the category rides as a form field', () async {
      final service = serviceReturning(row);

      final saved = await service.uploadAttachment(
        'e1',
        category: SapAttachmentCategory.rocCoc,
        bytes: List.filled(2048, 0),
        filename: 'roc.pdf',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/sap-proposal/attachments'));
      expect(saved.category, SapAttachmentCategory.rocCoc);
      expect(saved.filename, 'roc.pdf');
    });

    test('a file the server would refuse never leaves the phone', () async {
      final service = serviceReturning(row);

      expect(
        () => service.uploadAttachment(
          'e1',
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
      expect(files.single.revisionNo, 1);
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
