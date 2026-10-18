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
  SapForm({required this.eventId, SapService? service}) : _service = service;

  final String eventId;
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
    if (service == null) {
      _localOnly = true;
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
        p = await service.fetch(eventId);
      } on SapUnavailable {
        p = await service.create(eventId);
      }
      _adopt(p);
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
  Future<bool> _write(Future<SapProposal> Function(SapService, int) call) async {
    final service = _service;
    if (service == null) {
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
    (s, v) => s.saveDetails(eventId, expectedVersion: v, details: _details),
  );

  Future<bool> saveProgramFlow() => _write(
    (s, v) =>
        s.replaceProgramFlow(eventId, expectedVersion: v, items: _programFlow),
  );

  Future<bool> saveBudgetItems() => _write(
    (s, v) =>
        s.replaceBudgetItems(eventId, expectedVersion: v, items: _budgetItems),
  );

  Future<bool> saveSupportRequests() => _write(
    (s, v) => s.replaceSupportRequests(
      eventId,
      expectedVersion: v,
      items: _supportRequests,
    ),
  );

  Future<bool> saveAffectedClasses() => _write(
    (s, v) => s.replaceAffectedClasses(
      eventId,
      expectedVersion: v,
      items: _affectedClasses,
    ),
  );

  Future<bool> saveClearance() {
    final c = _clearance;
    if (c == null) return Future.value(false);
    return _write(
      (s, v) => s.saveClearance(eventId, expectedVersion: v, clearance: c),
    );
  }

  Future<bool> submit() =>
      _write((s, v) => s.submit(eventId, expectedVersion: v));

  Future<bool> evaluate({
    required SapEvaluationOutcome outcome,
    required String remarks,
  }) => _write(
    (s, v) => s.evaluate(
      eventId,
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

  /// A plain count for the hub's footer.
  int get completedParts => [
    for (final p in SapPart.values)
      if (statusOf(p) == SapPartStatus.complete) p,
  ].length;
}
