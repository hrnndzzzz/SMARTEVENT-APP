import 'api_client.dart';
import 'models/sap_proposal.dart';

/// Raised when the deployment this build talks to has no SAP routes.
///
/// The backend slice ships separately from the app, so a build can easily
/// be pointed at a server that predates it. Saying which half is behind
/// beats a screen that silently shows nothing.
class SapUnavailable implements Exception {
  const SapUnavailable();
}

/// Someone else changed the proposal first.
///
/// The backend uses an optimistic `expected_version` on every mutation.
/// A 409 here means the screen is stale: reload and let the user decide
/// what to do, and never blindly resend — the contract is explicit that a
/// retry can apply an edit on top of a change the user never saw.
class SapVersionConflict implements Exception {
  const SapVersionConflict(this.message, {this.blockers = const []});

  final String message;

  /// A 409 for readiness or incomplete predecessors carries these.
  final List<String> blockers;
}

/// A link to the stored scan. Short-lived by design.
class SapFinalScan {
  const SapFinalScan({
    required this.url,
    required this.expiresInSeconds,
    required this.sha256,
  });

  final String url;
  final int expiresInSeconds;
  final String sha256;
}

/// SAS-SDS-FO-020 (001): the Student Activity Proposal Form.
///
/// Every call lives under `/events/{id}/sap-proposal`. Collections are
/// replaced wholesale rather than appended to — the client edits its own
/// list and sends the whole thing with the current version — which is why
/// there is no add/remove call here.
class SapService {
  SapService(this._client);

  final ApiClient _client;
  bool get isReadOnly => !_client.canWriteRemote;
  Future<DownloadedFile> attachmentFile(String eventId, String attachmentId) =>
      _client.storedFile(
        '',
        linkPath: '${_base(eventId)}/attachments/$attachmentId/download',
        owner: '/events/$eventId',
      );
  Future<DownloadedFile> finalScanFile(String eventId) => _client.storedFile(
    '',
    linkPath: '${_base(eventId)}/final-signed-copy',
    owner: '/events/$eventId',
  );

  String _base(String eventId) => '/events/$eventId/sap-proposal';

  /// Translates the two failure shapes every mutation shares.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (error) {
      if (error.statusCode == 404) throw const SapUnavailable();
      if (error.statusCode == 409) {
        throw SapVersionConflict(error.message, blockers: _blockersOf(error));
      }
      rethrow;
    }
  }

  /// A 409 `detail` may be a string, an error array or a structured object
  /// with `message` and `blockers`. The contract warns not to assume one
  /// shape, so anything unrecognised simply yields no blockers.
  static List<String> _blockersOf(ApiException error) {
    final detail = error.detail;
    final found = detail is Map ? detail['blockers'] : null;
    return found is List ? [for (final b in found) '$b'] : const [];
  }

  SapProposal _proposal(Object? response) =>
      SapProposal.fromJson(Map<String, dynamic>.from(response as Map));

  /// `POST base` — starts a draft on an event that has none.
  Future<SapProposal> create(String eventId) => _guard(
    () async => _proposal(await _client.post(_base(eventId), body: const {})),
  );

  /// `GET base` — the current working aggregate.
  Future<SapProposal> fetch(String eventId) =>
      _guard(() async => _proposal(await _client.get(_base(eventId))));

  /// `PATCH base` — a partial save of Parts 1–3.
  ///
  /// Drafts allow incomplete saves; the cross-field time, class and budget
  /// checks only run at submission. Saving is not clearance.
  Future<SapProposal> saveDetails(
    String eventId, {
    required int expectedVersion,
    required SapDetails details,
  }) {
    return _guard(() async {
      final response = await _client.patch(
        _base(eventId),
        body: {
          'expected_version': expectedVersion,
          'details': details.toPatchJson(),
        },
      );
      return _proposal(response);
    });
  }

  Future<SapProposal> _replace(
    String eventId,
    String suffix,
    int expectedVersion,
    List<Map<String, dynamic>> items,
  ) {
    return _guard(() async {
      final response = await _client.put(
        '${_base(eventId)}$suffix',
        body: {'expected_version': expectedVersion, 'items': items},
      );
      return _proposal(response);
    });
  }

  /// `PUT /program-flow` — replaces the whole timed programme.
  Future<SapProposal> replaceProgramFlow(
    String eventId, {
    required int expectedVersion,
    required List<SapProgramFlowItem> items,
  }) => _replace(eventId, '/program-flow', expectedVersion, [
    for (final i in items) i.toJson(),
  ]);

  /// `PUT /budget-items` — replaces the whole breakdown.
  Future<SapProposal> replaceBudgetItems(
    String eventId, {
    required int expectedVersion,
    required List<SapBudgetItem> items,
  }) => _replace(eventId, '/budget-items', expectedVersion, [
    for (final i in items) i.toJson(),
  ]);

  /// `PUT /support-requests` — replaces all Part 2 requests.
  Future<SapProposal> replaceSupportRequests(
    String eventId, {
    required int expectedVersion,
    required List<SapSupportRequest> items,
  }) => _replace(eventId, '/support-requests', expectedVersion, [
    for (final i in items) i.toJson(),
  ]);

  /// `PUT /affected-classes` — an empty list clears the declaration, which
  /// is what "no class interruption" requires.
  Future<SapProposal> replaceAffectedClasses(
    String eventId, {
    required int expectedVersion,
    required List<SapAffectedClass> items,
  }) => _replace(eventId, '/affected-classes', expectedVersion, [
    for (final i in items) i.toJson(),
  ]);

  /// `PUT /sds-clearance` — SDS confirms Part 4.
  ///
  /// Any later edit to Parts 1–3 or a collection clears this again, and
  /// SDS has to confirm before the proposal can be submitted.
  Future<SapProposal> saveClearance(
    String eventId, {
    required int expectedVersion,
    required SapClearance clearance,
  }) {
    return _guard(() async {
      final response = await _client.put(
        '${_base(eventId)}/sds-clearance',
        body: {
          'expected_version': expectedVersion,
          'clearance': clearance.toJson(),
        },
      );
      return _proposal(response);
    });
  }

  /// Submitting, signing and printing make the server fill the official
  /// Word form and have Word print it: about 5 s, and up to 90 s when
  /// another print is ahead of it. Giving up sooner would report a timeout
  /// while the server goes on to finish, and the retry would then 409.
  static const _printing = Duration(seconds: 120);

  /// `POST /submit` — freezes the snapshot and PDF and creates all nine
  /// checkpoints. A 409 here usually carries readiness blockers.
  Future<SapProposal> submit(String eventId, {required int expectedVersion}) {
    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/submit',
        body: {'expected_version': expectedVersion},
        patience: _printing,
      );
      return _proposal(response);
    });
  }

  /// `POST /withdraw` — the proposer takes an unreviewed proposal back
  /// to draft so they can change or drop it.
  ///
  /// The server refuses with 409 once the SDS Office has started: a
  /// review row or any recorded checkpoint closes the door, and the way
  /// back is then a return for changes, not a withdrawal. It keeps the
  /// revision number and re-stages the attachments for the next submit,
  /// so nothing already submitted is erased.
  Future<SapProposal> withdraw(
    String eventId, {
    required int expectedVersion,
  }) {
    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/withdraw',
        body: {'expected_version': expectedVersion},
      );
      return _proposal(response);
    });
  }

  /// `POST /return` — sends it back for revision. The comment is required
  /// and must not be blank; resubmission creates a new revision, and old
  /// signatures are never carried across.
  Future<SapProposal> returnForRevision(
    String eventId, {
    required int expectedVersion,
    required String remarks,
  }) {
    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/return',
        body: {'expected_version': expectedVersion, 'remarks': remarks},
      );
      return _proposal(response);
    });
  }

  /// Section remarks as the server wants them: keyed by wire name, with
  /// the blank ones dropped. It strips empties itself, so sending them
  /// only risks tripping the 1000-character check on whitespace.
  Map<String, String> _sections(Map<SapRemarkSection, String> remarks) => {
    for (final entry in remarks.entries)
      if (entry.value.trim().isNotEmpty) entry.key.wireName: entry.value.trim(),
  };

  /// `PUT /sds-review` — saves the SDS Office's remarks without signing.
  ///
  /// Remarks can be written, read by the proposer and revised as often as
  /// the office likes while the revision is still pending. Signing is a
  /// separate, final act: see [sdsSign].
  Future<SapProposal> saveReviewNotes(
    String eventId, {
    required int expectedVersion,
    String overallRemarks = '',
    Map<SapRemarkSection, String> sectionRemarks = const {},
  }) {
    return _guard(() async {
      final response = await _client.put(
        '${_base(eventId)}/sds-review',
        body: {
          'expected_version': expectedVersion,
          'overall_remarks': overallRemarks.trim(),
          'section_remarks': _sections(sectionRemarks),
        },
      );
      return _proposal(response);
    });
  }

  /// `POST /sds-sign` — the SDS Office signs the pending revision.
  ///
  /// This is the one electronic signature in the whole form; the nine on
  /// paper stay paper. It locks the revision, moves the state to
  /// `sds_signed` and stores the signed PDF, so there is no undo: a
  /// proposal that needs changing afterwards is returned and resubmitted
  /// as a new revision, which must be signed again.
  ///
  /// Throws [ArgumentError] if the drawing is one the server would refuse,
  /// rather than making the signer draw it a second time to find out.
  Future<SapProposal> sdsSign(
    String eventId, {
    required int expectedVersion,
    required SapSignature signature,
    String overallRemarks = '',
    Map<SapRemarkSection, String> sectionRemarks = const {},
  }) {
    final problem = signature.problem;
    if (problem != null) throw ArgumentError(problem);

    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/sds-sign',
        body: {
          'expected_version': expectedVersion,
          'overall_remarks': overallRemarks.trim(),
          'section_remarks': _sections(sectionRemarks),
          'signature_strokes': signature.toJson(),
        },
        patience: _printing,
      );
      return _proposal(response);
    });
  }

  /// `GET /workflow` — the nine slots for the current revision.
  Future<SapWorkflow> workflow(String eventId) {
    return _guard(() async {
      final response = await _client.get('${_base(eventId)}/workflow');
      return SapWorkflow.fromJson(Map<String, dynamic>.from(response as Map));
    });
  }

  /// `POST /workflow/{step_id}/record` — SDS records that it inspected a
  /// physical signature.
  ///
  /// This is an administrative record of paper, not an electronic
  /// signature, and the UI must not describe it as one. Evidence recorded
  /// wrongly is never overwritten: return the proposal and start a fresh
  /// revision instead.
  Future<SapWorkflow> recordCheckpoint(
    String eventId, {
    required String stepId,
    required int expectedVersion,
    required SapCheckpointEvidence evidence,
  }) {
    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/workflow/$stepId/record',
        body: {'expected_version': expectedVersion, ...evidence.toJson()},
      );
      return SapWorkflow.fromJson(Map<String, dynamic>.from(response as Map));
    });
  }

  /// `POST /attachments` — a supporting file for the active revision.
  ///
  /// PDF, PNG or JPEG, up to 10 MB. The type and size are checked here
  /// first: a refusal costs the proposer the whole transfer before the
  /// server says why, which on a phone is a slow way to learn that a
  /// file was the wrong sort.
  ///
  /// Throws [ArgumentError] when the file is one the server would refuse.
  /// Like every mutation it moves the version, so the server answers with
  /// the whole proposal rather than the new file.
  Future<SapProposal> uploadAttachment(
    String eventId, {
    required int expectedVersion,
    required SapAttachmentCategory category,
    required List<int> bytes,
    required String filename,
  }) {
    final problem = SapUploadLimits.problemWith(filename, bytes.length);
    if (problem != null) throw ArgumentError(problem);

    return _guard(() async {
      final response = await _client.upload(
        '${_base(eventId)}/attachments',
        field: 'file',
        bytes: bytes,
        filename: filename,
        contentType: SapUploadLimits.contentTypeFor(filename)!,
        fields: {
          'expected_version': '$expectedVersion',
          'category': category.wireName,
        },
      );
      return _proposal(response);
    });
  }

  /// `GET /attachments` — the files on the draft or current revision.
  Future<List<SapAttachment>> attachments(String eventId) {
    return _guard(() async {
      final response = await _client.get('${_base(eventId)}/attachments');
      // A bare list, or one wrapped the way the collections are. The
      // contract does not promise which, and guessing wrong is how the
      // collections came back empty the first time.
      final rows = response is List
          ? response
          : (response as Map)['attachments'] as List? ?? const [];
      return [
        for (final row in rows)
          SapAttachment.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    });
  }

  /// `GET /attachments/{id}/download` — a short-lived private link.
  ///
  /// The link expires in minutes and points at private storage. It is
  /// never to be logged, cached or sent anywhere else.
  Future<SapFinalScan> attachmentLink(String eventId, String attachmentId) {
    return _guard(() async {
      final response = await _client.get(
        '${_base(eventId)}/attachments/$attachmentId/download',
      );
      final row = Map<String, dynamic>.from(response as Map);
      return SapFinalScan(
        url: row['url'] as String,
        expiresInSeconds: (row['expires_in'] as num?)?.toInt() ?? 0,
        sha256: (row['sha256'] as String?) ?? '',
      );
    });
  }

  /// `GET /pdf` — the printable six-page form.
  ///
  /// A draft preview while the proposal is still editable, otherwise the
  /// stored bytes of the submitted revision. [revisionNo] fetches an
  /// earlier printed copy instead.
  ///
  /// A revision the SDS Office has signed prints as the copy stored at
  /// signing: the signer's name and drawn signature in the SDS Coordinator's
  /// cell, the watermark "SIGNED AND APPROVED BY SDS OFFICE" and the footer
  /// "SAP revision N | SDS signed". The rejected current revision prints with
  /// the watermark "REJECTED BY THE SDS OFFICE"; any other prints "Unsigned".
  /// The other signature slots always print empty, and the signed scan, a
  /// separate download, is the evidence of the paper signatures.
  Future<DownloadedFile> pdf(String eventId, {int? revisionNo}) {
    return _guard(() async {
      return _client.download(
        '${_base(eventId)}/pdf',
        query: revisionNo == null ? null : {'revision_no': '$revisionNo'},
        expectedContentType: 'application/pdf',
        fallbackFilename: 'SAS-SDS-FO-020.pdf',
        patience: _printing,
      );
    });
  }

  /// `POST /final-signed-copy` — the scanned, signed paper.
  ///
  /// Write-once: there is deliberately no replacement after approval, so
  /// the caller should be sure before sending. The server takes it only
  /// while the proposal is `sds_signed` with all nine checkpoints recorded,
  /// and only as an unencrypted PDF of at most 10 MB with at least three
  /// pages and the same page count as the SDS-signed copy (the form and its
  /// addenda), and no forms, actions, annotations or embedded files, which
  /// is what flattening a scan produces.
  Future<SapProposal> uploadFinalScan(
    String eventId, {
    required int expectedVersion,
    required List<int> bytes,
    required String filename,
  }) {
    return _guard(() async {
      final response = await _client.upload(
        '${_base(eventId)}/final-signed-copy',
        field: 'file',
        bytes: bytes,
        filename: filename,
        contentType: 'application/pdf',
        fields: {'expected_version': '$expectedVersion'},
      );
      return _proposal(response);
    });
  }

  /// `GET /final-signed-copy` — a short-lived private link to the scan,
  /// with the digest the server stored for it.
  ///
  /// SDS only, and the link expires in minutes. Never put it in a log, a
  /// cache or analytics: it is a signed URL to private evidence.
  Future<SapFinalScan> finalScan(String eventId) {
    return _guard(() async {
      final response = await _client.get('${_base(eventId)}/final-signed-copy');
      final row = Map<String, dynamic>.from(response as Map);
      return SapFinalScan(
        url: row['url'] as String,
        expiresInSeconds: (row['expires_in'] as num?)?.toInt() ?? 0,
        sha256: (row['sha256'] as String?) ?? '',
      );
    });
  }

  /// `POST /evaluation` — Part 6, recorded once after the activity.
  ///
  /// Completing administration is not the same as the activity having been
  /// conducted: analytics must read the outcome to tell a cancellation
  /// from a conduct, and neither waives the existing closeout reports.
  Future<SapProposal> evaluate(
    String eventId, {
    required int expectedVersion,
    required SapEvaluationOutcome outcome,
    required String remarks,
  }) {
    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/evaluation',
        body: {
          'expected_version': expectedVersion,
          'outcome': outcome.wireName,
          'remarks': remarks,
        },
      );
      return _proposal(response);
    });
  }
}
