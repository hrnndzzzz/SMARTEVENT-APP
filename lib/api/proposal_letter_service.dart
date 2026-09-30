import 'api_client.dart';
import 'models/proposal_letter.dart';

/// Event proposal letters.
///
/// Read access reaches further than write: SDS Staff and Super Admin see
/// every letter in the school, while Treasurer, Adviser and Admin see their
/// own department's. Officers have no access at all.
///
/// There is no edit, delete or review endpoint — only list, read and
/// upload.
class ProposalLetterService {
  final ApiClient _client;
  ProposalLetterService(this._client);

  Future<List<ProposalLetter>> list() async {
    final response = await _client.get('/proposal-letters');
    return (response as List)
        .map((json) => ProposalLetter.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ProposalLetter> get(String letterId) async {
    final response = await _client.get('/proposal-letters/$letterId');
    return ProposalLetter.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /proposal-letters` — Treasurer, Adviser, Admin or Super Admin.
  ///
  /// Multipart, with `event_id` and `title` as form fields alongside the
  /// file. PDF, JPEG or PNG, up to 10 MB.
  ///
  /// Uploading a letter is separate from submitting or approving the event
  /// — it neither advances nor requires the event's review.
  Future<ProposalLetter> upload({
    required String eventId,
    required String title,
    required List<int> bytes,
    required String filename,
  }) async {
    final contentType = proposalLetterContentTypeFor(filename);
    if (contentType == null) {
      throw ArgumentError(
        'Proposal letters must be PDF, JPEG or PNG — got "$filename".',
      );
    }

    final response = await _client.upload(
      '/proposal-letters',
      field: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: {'event_id': eventId, 'title': title},
    );
    return ProposalLetter.fromJson((response as Map).cast<String, dynamic>());
  }

  /// The backend's cap, checked before upload so the failure is explained
  /// rather than being a bare 400.
  static const int maxBytes = 10 * 1024 * 1024;
}
