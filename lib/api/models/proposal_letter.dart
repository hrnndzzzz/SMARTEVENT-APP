/// A formal proposal-letter document submitted for an event — the
/// backend's `EventProposalLetterOut`.
///
/// Deliberately separate from the event record itself. This is the entire
/// reason the SDS Staff role exists: reading these is its only permission,
/// and it must never reach the event or finance data behind them.
///
/// There is no edit, delete or review-status endpoint, so the app offers
/// none of those.
class ProposalLetter {
  final String id;
  final String eventId;
  final String title;

  /// Where the document lives. Opening it is not the same as downloading a
  /// protected report — do not claim signed-URL protection the deployment
  /// may not have.
  final String documentUrl;

  /// The backend returns an id, not a display name, and fetching `/users`
  /// to decorate it would 403 for SDS Staff. Shown as-is.
  final String submittedBy;

  final DateTime createdAt;

  ProposalLetter({
    required this.id,
    required this.eventId,
    required this.title,
    required this.documentUrl,
    required this.submittedBy,
    required this.createdAt,
  });

  /// Best guess at the document kind from the stored URL, for choosing an
  /// icon. Only ever cosmetic.
  bool get looksLikePdf => documentUrl.toLowerCase().endsWith('.pdf');

  factory ProposalLetter.fromJson(Map<String, dynamic> json) {
    return ProposalLetter(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      documentUrl: json['document_url'] as String,
      submittedBy: json['submitted_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Document types the letter endpoint accepts — PDF, JPEG and PNG.
///
/// Deliberately a different set from receipts, which take images only and
/// also allow WebP and HEIC. The backend matches on the multipart part's
/// content type and does not look at the filename, so this mapping has to
/// be right.
const Map<String, String> proposalLetterTypes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
};

/// The media type for [filename], or null when it isn't an accepted kind.
String? proposalLetterContentTypeFor(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return null;
  return proposalLetterTypes[filename.substring(dot + 1).toLowerCase()];
}
