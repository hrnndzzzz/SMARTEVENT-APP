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
    final found = error.fieldErrors['blockers'];
    if (found == null || found.isEmpty) return const [];
    return found
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  SapProposal _proposal(Object? response) =>
      SapProposal.fromJson(Map<String, dynamic>.from(response as Map));

  /// `POST base` — starts a draft on an event that has none.
  Future<SapProposal> create(String eventId) =>
      _guard(() async => _proposal(await _client.post(_base(eventId), body: const {})));

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

  /// `POST /submit` — freezes the snapshot and PDF and creates all nine
  /// checkpoints. A 409 here usually carries readiness blockers.
  Future<SapProposal> submit(
    String eventId, {
    required int expectedVersion,
  }) {
    return _guard(() async {
      final response = await _client.post(
        '${_base(eventId)}/submit',
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

  /// `GET /pdf` — the printable six-page form.
  ///
  /// A draft preview while the proposal is still editable, otherwise the
  /// stored bytes of the submitted revision. [revisionNo] fetches an
  /// earlier printed copy instead.
  ///
  /// It stays an unsigned printable copy even after approval: the signed
  /// scan is a separate download, and nothing stamps a signature or an
  /// approval mark onto these bytes.
  Future<DownloadedFile> pdf(String eventId, {int? revisionNo}) {
    return _guard(() async {
      return _client.download(
        '${_base(eventId)}/pdf',
        query: revisionNo == null ? null : {'revision_no': '$revisionNo'},
        expectedContentType: 'application/pdf',
        fallbackFilename: 'SAS-SDS-FO-020.pdf',
      );
    });
  }

  /// `POST /final-signed-copy` — the scanned, signed paper.
  ///
  /// Write-once: there is deliberately no replacement after approval, so
  /// the caller should be sure before sending. The server requires
  /// exactly six unencrypted pages with no forms or annotations, which is
  /// what flattening a scan produces.
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
