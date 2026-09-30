import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/remote_expense.dart';

/// The receipt endpoints validate the multipart part's `content_type`
/// against a fixed allow-list and never look at the filename.
///
/// Sending a file without an explicit type makes it default to
/// `application/octet-stream`, which the backend rejects as "Unsupported
/// file type" — a real bug that shipped once, because the upload helper
/// assumed the server would infer the type from the extension.
void main() {
  group('extension to media type', () {
    test('maps every accepted image extension', () {
      expect(receiptContentTypeFor('receipt.jpg'), 'image/jpeg');
      expect(receiptContentTypeFor('receipt.jpeg'), 'image/jpeg');
      expect(receiptContentTypeFor('receipt.png'), 'image/png');
      expect(receiptContentTypeFor('receipt.webp'), 'image/webp');
      expect(receiptContentTypeFor('receipt.heic'), 'image/heic');
    });

    test('is case-insensitive, since cameras vary', () {
      expect(receiptContentTypeFor('IMG_0042.JPG'), 'image/jpeg');
      expect(receiptContentTypeFor('Scan.HEIC'), 'image/heic');
    });

    test('handles a name with several dots', () {
      expect(receiptContentTypeFor('2026.09.30.receipt.png'), 'image/png');
    });

    test('rejects types the backend does not accept', () {
      expect(receiptContentTypeFor('receipt.pdf'), isNull);
      expect(receiptContentTypeFor('receipt.gif'), isNull);
      expect(receiptContentTypeFor('receipt.txt'), isNull);
    });

    test('rejects a name with no usable extension', () {
      expect(receiptContentTypeFor('receipt'), isNull);
      expect(receiptContentTypeFor('receipt.'), isNull);
      expect(receiptContentTypeFor(''), isNull);
    });

    test('never yields octet-stream, which is what the bug sent', () {
      for (final type in receiptImageTypes.values) {
        expect(type, startsWith('image/'));
        expect(type, isNot('application/octet-stream'));
      }
    });

    test('every mapped extension is lowercase in the table', () {
      // Lookup lowercases the input, so an uppercase key would be dead.
      for (final extension in receiptImageTypes.keys) {
        expect(extension, extension.toLowerCase());
      }
    });
  });
}
