import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models/sap_proposal.dart';
import '../api/sap_service.dart';

/// Which of the six parts a screen is editing.
enum SapPart {
  one(1, 'Activity Details'),
  two(2, 'School Support'),
  three(3, 'Additional Information'),
  four(4, 'SDS Office Clearance'),
  five(5, 'University Clearance'),
  six(6, 'Evaluation');

  const SapPart(this.number, this.title);

  final int number;
  final String title;

  /// Who fills this part in. Parts 4 to 6 are the SDS Office's, and the
  /// paper form says so in red at the top of each.
  bool get isSdsOnly => number >= 4;
}

/// How far along one part is, for the hub's list.
enum SapPartStatus { empty, partial, complete, locked }

/// The working copy of a SAS-SDS-FO-020 proposal.
///
/// It holds the form as it is being filled in, saving each part to the
/// backend as the user finishes with it. The collections are kept whole
/// because the API replaces them wholesale — there is no row-append
/// endpoint, by design — so editing a budget line means editing this list
/// and sending all of it.
///
/// When the backend has no SAP routes the form still works: edits are
/// kept here and [isLocalOnly] goes true, so the screens can say that
/// nothing is saved yet rather than pretending or failing. That matters
/// while the backend slice is still landing.
class SapForm extends ChangeNotifier {
  // The lint wants `this._service`, which Dart does not allow as a named
  // parameter, private names being illegal there.
  // ignore: prefer_initializing_formals
  SapForm({String? eventId, SapService? service, this.seed})
    : _eventId = eventId,
      _service = service;

  /// What the event was created with, carried into the form.
  ///
  /// The two forms ask for the same things — title, school year, scope,
  /// date, budget — and typing them twice is the sort of thing that
  /// makes people stop filling in the second one. Applied only to a
  /// proposal with nothing in it yet, so it can never overwrite what
  /// somebody has already written.
  final SapDetails? seed;

  /// Null until there is an event to hang the proposal on.
  ///
  /// Filling the form is how an event gets made now, so the first two
  /// parts are written before any record exists. Nothing is sent while
  /// this is null; the edits sit here until the event is created and
  /// [bindEvent] is called.
  String? _eventId;
  String? get eventId => _eventId;
  bool get hasEvent => _eventId != null;

  final SapService? _service;

  SapProposal? _proposal;
  SapProposal? get proposal => _proposal;

  SapDetails _details = const SapDetails();
  SapDetails get details => _details;

  List<SapProgramFlowItem> _programFlow = [];
  List<SapBudgetItem> _budgetItems = [];
  List<SapSupportRequest> _supportRequests = [];
  List<SapAffectedClass> _affectedClasses = [];
  SapClearance? _clearance;

  List<SapProgramFlowItem> get programFlow => List.unmodifiable(_programFlow);
  List<SapBudgetItem> get budgetItems => List.unmodifiable(_budgetItems);
  List<SapSupportRequest> get supportRequests =>
      List.unmodifiable(_supportRequests);
  List<SapAffectedClass> get affectedClasses =>
      List.unmodifiable(_affectedClasses);
  SapClearance? get clearance => _clearance;

  bool _loading = false;
  bool get loading => _loading;

  bool _saving = false;
  bool get saving => _saving;

  String? _error;
  String? get error => _error;

  /// The backend has no SAP routes, or none was supplied. Everything
  /// typed stays on this device.
  bool _localOnly = false;
  bool get isLocalOnly => _localOnly || _service == null;

  /// Someone else changed the proposal while this screen was open. The
  /// contract is explicit that the answer is to reload, never to resend.
  bool _stale = false;
  bool get isStale => _stale;

  SapState? get state => _proposal?.state;

  int get version => _proposal?.version ?? 0;

  /// Parts 1 to 3 are the proposer's, and only while the proposal is a
  /// draft or has been returned.
  bool get canEditProposerParts =>
      isLocalOnly || (_proposal?.isProposerEditable ?? true);

  /// Loads the proposal, creating the draft if the event has none.
  Future<void> load() async {
    final service = _service;
    // No event yet means nothing to fetch: this form is how one gets
    // made, so it starts empty and local by definition.
    if (service == null || _eventId == null) {
      _localOnly = true;
      _applySeed();
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // A 404 means either "this event has no proposal yet" or "this
      // backend has no SAP routes", and the status alone cannot tell them
      // apart. Creating one settles it: if that works the event simply
      // had none, and if it 404s too the slice is genuinely absent.
      SapProposal p;
      try {
        p = await service.fetch(_eventId!);
      } on SapUnavailable {
        p = await service.create(_eventId!);
      }
      _adopt(p);
      _applySeed();
      _localOnly = false;
    } on SapUnavailable {
      // The backend predates this slice. Keep whatever is typed.
      _localOnly = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Fills an empty form from what the event was created with. A title
  /// already present means somebody has been here, and nothing is
  /// touched.
  void _applySeed() {
    final from = seed;
    if (from == null) return;
    if ((_details.title ?? '').isNotEmpty) return;

    _details = _details.copyWith(
      title: from.title,
      organizationName: from.organizationName,
      schoolYear: from.schoolYear,
      scope: from.scope,
      activityDate: from.activityDate,
      proposalDate: from.proposalDate,
      totalBudget: from.totalBudget,
      rationale: from.rationale,
    );
  }

  void _adopt(SapProposal p) {
    _proposal = p;
    _details = p.details;
    _programFlow = [...p.programFlow];
    _budgetItems = [...p.budgetItems];
    _supportRequests = [...p.supportRequests];
    _affectedClasses = [...p.affectedClasses];
    _clearance = p.clearance;
    _stale = false;
  }

  // --- local edits ---------------------------------------------------------

  void updateDetails(SapDetails Function(SapDetails) change) {
    _details = change(_details);
    notifyListeners();
  }

  void setProgramFlow(List<SapProgramFlowItem> items) {
    _programFlow = [...items];
    notifyListeners();
  }

  void setBudgetItems(List<SapBudgetItem> items) {
    _budgetItems = [...items];
    notifyListeners();
  }

  void setSupportRequests(List<SapSupportRequest> items) {
    _supportRequests = [...items];
    notifyListeners();
  }

  void setAffectedClasses(List<SapAffectedClass> items) {
    _affectedClasses = [...items];
    notifyListeners();
  }

  void setClearance(SapClearance? value) {
    _clearance = value;
    notifyListeners();
  }

  // --- saving --------------------------------------------------------------

  /// Runs one write, translating the two failures every write shares.
  /// Returns false when nothing was saved.
  /// Attaches this form to the event it just caused to exist, and
  /// pushes everything written so far.
  Future<void> bindEvent(String id) async {
    if (_eventId != null) return;
    _eventId = id;
    notifyListeners();
    if (_service == null) return;

    // Everything written before the event existed, held aside: load()
    // creates the proposal and adopts the server's empty version of it,
    // which would otherwise wipe exactly what we are here to send.
    final written = _details;
    final flow = [..._programFlow];
    final budget = [..._budgetItems];
    final support = [..._supportRequests];
    final classes = [..._affectedClasses];

    await load();

    _details = written;
    _programFlow = flow;
    _budgetItems = budget;
    _supportRequests = support;
    _affectedClasses = classes;
    notifyListeners();

    await saveDetails();
    if (flow.isNotEmpty) await saveProgramFlow();
    if (budget.isNotEmpty) await saveBudgetItems();
    if (support.isNotEmpty) await saveSupportRequests();
    if (classes.isNotEmpty) await saveAffectedClasses();
  }

  Future<bool> _write(Future<SapProposal> Function(SapService, int) call) async {
    final service = _service;
    if (service == null || _eventId == null) {
      _localOnly = true;
      notifyListeners();
      return true; // Kept locally, which the screens say out loud.
    }

    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await call(service, version);
      _adopt(updated);
      _localOnly = false;
      return true;
    } on SapUnavailable {
      _localOnly = true;
      return true;
    } on SapVersionConflict catch (conflict) {
      _stale = true;
      _error = conflict.blockers.isEmpty
          ? conflict.message
          : conflict.blockers.join('\n');
      return false;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> saveDetails() => _write(
    (s, v) => s.saveDetails(_eventId!, expectedVersion: v, details: _details),
  );

  Future<bool> saveProgramFlow() => _write(
    (s, v) =>
        s.replaceProgramFlow(_eventId!, expectedVersion: v, items: _programFlow),
  );

  Future<bool> saveBudgetItems() => _write(
    (s, v) =>
        s.replaceBudgetItems(_eventId!, expectedVersion: v, items: _budgetItems),
  );

  Future<bool> saveSupportRequests() => _write(
    (s, v) => s.replaceSupportRequests(
      _eventId!,
      expectedVersion: v,
      items: _supportRequests,
    ),
  );

  Future<bool> saveAffectedClasses() => _write(
    (s, v) => s.replaceAffectedClasses(
      _eventId!,
      expectedVersion: v,
      items: _affectedClasses,
    ),
  );

  Future<bool> saveClearance() {
    final c = _clearance;
    if (c == null) return Future.value(false);
    return _write(
      (s, v) => s.saveClearance(_eventId!, expectedVersion: v, clearance: c),
    );
  }

  Future<bool> submit() =>
      _write((s, v) => s.submit(_eventId!, expectedVersion: v));

  SapWorkflow? _workflow;
  SapWorkflow? get workflow => _workflow;

  /// Loads the nine slots. Returns quietly when the backend has no SAP
  /// routes, since the screen shows the blank form in that case.
  Future<void> loadWorkflow() async {
    final service = _service;
    if (service == null) return;
    try {
      _workflow = await service.workflow(_eventId!);
    } on SapUnavailable {
      _localOnly = true;
    } catch (_) {
      // The slots are a view of something already on screen; failing to
      // refresh them is not worth an error banner of its own.
    }
    notifyListeners();
  }

  /// Records that SDS inspected one signed page.
  Future<bool> recordCheckpoint({
    required String stepId,
    required SapCheckpointEvidence evidence,
  }) async {
    final service = _service;
    if (service == null) {
      _localOnly = true;
      notifyListeners();
      return false;
    }

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      _workflow = await service.recordCheckpoint(
        _eventId!,
        stepId: stepId,
        expectedVersion: version,
        evidence: evidence,
      );
      // The proposal's own version moved with it.
      await load();
      return true;
    } on SapVersionConflict catch (conflict) {
      _stale = true;
      _error = conflict.message;
      return false;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Fetches the printable form. Returns null when there is nothing to
  /// print yet or the backend has no SAP routes.
  Future<DownloadedFile?> printableForm({int? revisionNo}) async {
    final service = _service;
    if (service == null) {
      _localOnly = true;
      notifyListeners();
      return null;
    }
    _error = null;
    try {
      return await service.pdf(_eventId!, revisionNo: revisionNo);
    } on SapUnavailable {
      _localOnly = true;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
    }
    notifyListeners();
    return null;
  }

  /// Uploads the signed scan. Write-once on the server, so this is the
  /// one action here with no second chance.
  /// Supporting files on the current draft or revision, newest call
  /// wins. Empty until [loadAttachments] has run once.
  List<SapAttachment> get attachments => List.unmodifiable(_attachments);
  List<SapAttachment> _attachments = const [];

  /// Whether the ROC or COC the server insists on for an off-campus
  /// submission is already attached.
  bool get hasRocCoc =>
      _attachments.any((a) => a.category == SapAttachmentCategory.rocCoc);

  Future<void> loadAttachments() async {
    final service = _service;
    if (service == null || _eventId == null) return;
    try {
      _attachments = await service.attachments(_eventId!);
      notifyListeners();
    } catch (_) {
      // A listing that fails leaves what was there. The proposer is
      // told what is missing at submission either way, and an error
      // banner over a side list is noise while they are still typing.
    }
  }

  /// Attaches a supporting file. Returns the reason it was refused, or
  /// null when it went.
  Future<String?> attachFile({
    required SapAttachmentCategory category,
    required List<int> bytes,
    required String filename,
  }) async {
    final service = _service;
    if (service == null || _eventId == null) {
      return 'This proposal has not been saved to the server yet.';
    }

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await service.uploadAttachment(
        _eventId!,
        category: category,
        bytes: bytes,
        filename: filename,
      );
      _attachments = [..._attachments, saved];
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    } catch (e) {
      return e is ApiException ? e.message : e.toString();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Remarks the SDS Office has written but not yet signed off.
  ///
  /// Kept here so the screen can show what was last saved and so an
  /// unsent edit is not lost when the screen rebuilds.
  Map<SapRemarkSection, String> sectionRemarks = {};
  String overallRemarks = '';

  /// `PUT /sds-review` — saves remarks without signing. Returns the
  /// reason it failed, or null.
  Future<String?> saveReviewNotes() async {
    final service = _service;
    if (service == null || _eventId == null) {
      return 'This proposal has not been saved to the server yet.';
    }

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      _adopt(
        await service.saveReviewNotes(
          _eventId!,
          expectedVersion: version,
          overallRemarks: overallRemarks,
          sectionRemarks: sectionRemarks,
        ),
      );
      return null;
    } on SapVersionConflict catch (conflict) {
      _stale = true;
      _error = conflict.message;
      return conflict.message;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
      return _error;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// `POST /sds-sign` — signs the pending revision.
  ///
  /// Final: it locks the revision and stores the signed PDF. A proposal
  /// that needs changing afterwards is returned and signed again as a
  /// new revision.
  Future<String?> sdsSign(SapSignature signature) async {
    final service = _service;
    if (service == null || _eventId == null) {
      return 'This proposal has not been saved to the server yet.';
    }

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      _adopt(
        await service.sdsSign(
          _eventId!,
          expectedVersion: version,
          signature: signature,
          overallRemarks: overallRemarks,
          sectionRemarks: sectionRemarks,
        ),
      );
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    } on SapVersionConflict catch (conflict) {
      _stale = true;
      _error = conflict.message;
      return conflict.message;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
      return _error;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> uploadFinalScan({
    required List<int> bytes,
    required String filename,
  }) async {
    final service = _service;
    if (service == null) return false;

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      _adopt(
        await service.uploadFinalScan(
          _eventId!,
          expectedVersion: version,
          bytes: bytes,
          filename: filename,
        ),
      );
      return true;
    } on SapVersionConflict catch (conflict) {
      _stale = true;
      _error = conflict.message;
      return false;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Sends the proposal back for revision. The comment is required.
  Future<bool> returnForRevision(String remarks) => _write(
    (s, v) => s.returnForRevision(_eventId!, expectedVersion: v, remarks: remarks),
  );

  Future<bool> evaluate({
    required SapEvaluationOutcome outcome,
    required String remarks,
  }) => _write(
    (s, v) => s.evaluate(
      _eventId!,
      expectedVersion: v,
      outcome: outcome,
      remarks: remarks,
    ),
  );

  // --- completion ----------------------------------------------------------

  /// What the hub shows beside each part.
  ///
  /// This is guidance, not validation: the backend runs the cross-field
  /// time, class and budget checks at submission, and a green tick here
  /// is not clearance.
  SapPartStatus statusOf(SapPart part) {
    switch (part) {
      case SapPart.one:
        final filled = _part1Filled;
        if (filled == 0) return SapPartStatus.empty;
        return filled == _part1Total
            ? SapPartStatus.complete
            : SapPartStatus.partial;
      case SapPart.two:
        return _supportRequests.isEmpty
            ? SapPartStatus.empty
            : SapPartStatus.complete;
      case SapPart.three:
        final any =
            (_details.additionalInformation ?? '').isNotEmpty ||
            _budgetItems.isNotEmpty ||
            _affectedClasses.isNotEmpty;
        if (!any) return SapPartStatus.empty;
        return _budgetItems.isEmpty
            ? SapPartStatus.partial
            : SapPartStatus.complete;
      case SapPart.four:
        return _clearance == null
            ? SapPartStatus.empty
            : SapPartStatus.complete;
      case SapPart.five:
        // Nothing exists until the proposal has been submitted once.
        final s = state;
        if (s == null || s == SapState.draft) return SapPartStatus.locked;
        return SapPartStatus.partial;
      case SapPart.six:
        if (_proposal?.evaluation != null) return SapPartStatus.complete;
        return state == SapState.approved
            ? SapPartStatus.empty
            : SapPartStatus.locked;
    }
  }

  static const int _part1Total = 12;

  int get _part1Filled {
    final d = _details;
    var n = 0;
    if ((d.title ?? '').isNotEmpty) n++;
    if ((d.organizationName ?? '').isNotEmpty) n++;
    if (d.activityDate != null) n++;
    if (d.startTime != null && d.endTime != null) n++;
    if (d.modality != null) n++;
    if (d.setting != null) n++;
    if ((d.venue ?? '').isNotEmpty) n++;
    if (d.expectedStudents != null) n++;
    if ((d.rationale ?? '').isNotEmpty) n++;
    if ((d.objectives ?? '').isNotEmpty) n++;
    if (d.coreValues.isNotEmpty) n++;
    if (_programFlow.isNotEmpty) n++;
    return n;
  }

  /// Puts the form into a given state without a server, for tests and
  /// for the offline demo. Not a shortcut around the API: nothing here
  /// is ever sent anywhere.
  @visibleForTesting
  void adoptForTest({SapState? state, SapDetails? details}) {
    _proposal = SapProposal(
      id: 'test',
      eventId: _eventId ?? '',
      state: state ?? SapState.draft,
      version: 1,
      revisionNo: 0,
      formCode: 'SAS-SDS-FO-020',
      formVersion: '001',
      details: details ?? _details,
      programFlow: _programFlow,
      budgetItems: _budgetItems,
      supportRequests: _supportRequests,
      affectedClasses: _affectedClasses,
      clearance: _clearance,
    );
    if (details != null) _details = details;
    notifyListeners();
  }

  /// A plain count for the hub's footer.
  int get completedParts => [
    for (final p in SapPart.values)
      if (statusOf(p) == SapPartStatus.complete) p,
  ].length;
}
