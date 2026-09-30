import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/category_service.dart';
import '../api/models/academic.dart';
import '../api/models/admin.dart';
import '../api/admin_service.dart';
import '../api/models/category.dart';
import '../api/models/income.dart';
import '../api/models/inventory.dart';
import '../api/inventory_service.dart';
import '../api/models/proposal_letter.dart';
import '../api/models/reports.dart';
import '../api/reports_service.dart';
import '../api/models/receipt.dart';
import '../api/proposal_letter_service.dart';
import '../api/income_service.dart';
import '../api/models/scope.dart';
import '../api/receipt_service.dart';
import '../api/scope_service.dart';
import '../api/models/money.dart';
import '../api/event_service.dart';
import '../api/models/remote_event.dart';
import '../api/expense_service.dart';
import '../api/models/remote_expense.dart';
import '../api/models/registration_result.dart';
import '../api/models/user_profile.dart';
import 'user_role.dart';

// Semester, EventScope and SchoolYear are part of the event vocabulary the
// screens work in, so they are re-exported alongside UserRole rather than
// making every screen import the API layer directly.
export '../api/models/academic.dart';

// Roster entries, managed accounts and audit rows for the admin screens.
export '../api/models/admin.dart';

// Category is the shape the pickers and list screens render directly.
export '../api/models/category.dart';

// Department and Organization are rendered directly by the scope pickers.
export '../api/models/scope.dart';

// Receipt and its review vocabulary are rendered by the receipts screens.
export '../api/models/receipt.dart';

// Proposal letters are rendered by the letters screen.
export '../api/models/proposal_letter.dart';

// Dashboard, report and export shapes are rendered by the report screens.
export '../api/models/reports.dart';
export '../api/reports_service.dart' show ReportsService;
export '../api/api_client.dart' show DownloadedFile;
export '../api/proposal_letter_service.dart' show ProposalLetterService;

// Income and its fund sources are rendered by the income screens.
export '../api/models/income.dart';

// Inventory items, movements and the signed-change helper.
export '../api/models/inventory.dart';
export '../api/inventory_service.dart' show InventoryService;
export '../api/receipt_service.dart' show ReceiptService;

// ApprovalRecord is the shape of a review-timeline row, which the event
// detail screen renders directly.
export '../api/models/remote_event.dart' show ApprovalRecord;

// Expense line items, scan results, payment methods and the money helper
// are all part of what the expense screens work with directly.
export '../api/models/money.dart';
export '../api/models/remote_expense.dart'
    show
        RemoteExpense,
        ExpenseLine,
        ExpenseLineInput,
        ItemCategory,
        ItemCategoryNaming,
        PaymentMethod,
        PaymentMethodNaming,
        PurchaseCompletionInput,
        PurchaseLineConfirmation,
        purchaseCompletionProblem,
        ReceiptDetailsInput,
        ScannedReceipt,
        receiptContentTypeFor,
        receiptImageTypes,
        ScannedReceiptLine;

// UserRole and its capability helpers live in user_role.dart; re-exported
// so the many `import '../state/app_state.dart'` screens keep working.
export 'user_role.dart';

/// Every status the backend can return for an event.
///
/// `draft` and `completed` used to be folded into "pending adviser", which
/// meant an unsubmitted draft looked like it was awaiting review and a
/// finished event looked unreviewed. The two pending stages stay separate
/// because lists and dashboard counts must show them separately.
///
/// There is no route that sets `completed` — the backend does it. Never
/// offer a Complete button or PATCH the status to fake one.
enum EventApprovalStatus { draft, pendingAdviser, pendingAdmin, approved, rejected, completed }

extension EventApprovalStatusInfo on EventApprovalStatus {
  /// Still being written — not yet in anyone's review queue.
  bool get isDraft => this == EventApprovalStatus.draft;

  /// Awaiting a decision at either stage.
  bool get isPending =>
      this == EventApprovalStatus.pendingAdviser ||
      this == EventApprovalStatus.pendingAdmin;

  /// Editable and resubmittable by its proposer.
  bool get isEditable =>
      this == EventApprovalStatus.draft || this == EventApprovalStatus.rejected;

  /// Review has finished, one way or the other.
  bool get isResolved =>
      this == EventApprovalStatus.approved ||
      this == EventApprovalStatus.rejected ||
      this == EventApprovalStatus.completed;
}

class EventItem {
  String? remoteId; // real backend UUID, null for locally-created-not-yet-synced events
  String title;
  String org;
  String date;
  String budget;

  EventApprovalStatus status;
  String? rejectedBy;
  String? adviserApprovalNote;
  String? adminApprovalNote;

  /// Academic metadata. Required on new events; null only on legacy rows
  /// that predate it, which an Admin repairs through the academic-metadata
  /// route rather than an ordinary edit.
  String? schoolYear;
  Semester? semester;
  EventScope? eventScope;

  /// Who proposed it, for the self-review guard: nobody may approve or
  /// reject their own proposal, so the controls are hidden when this
  /// matches the signed-in user. The API enforces it too.
  String? proposedBy;

  /// True when any academic field is missing.
  bool get hasIncompleteAcademicMetadata =>
      schoolYear == null || semester == null || eventScope == null;

  /// Compact "2026-2027 · 1st sem · Departmental" for list rows, with
  /// whatever is actually known.
  String get academicLabel {
    final parts = [
      if (schoolYear != null) schoolYear!,
      if (semester != null) semester!.shortLabel,
      if (eventScope != null) eventScope!.label,
    ];
    return parts.isEmpty ? 'No school year set' : parts.join(' · ');
  }

  String get statusLabel => switch (status) {
    EventApprovalStatus.draft => 'Draft',
    EventApprovalStatus.pendingAdviser => 'Pending Adviser Review',
    EventApprovalStatus.pendingAdmin => 'Pending Admin Approval',
    EventApprovalStatus.approved => 'Approved',
    EventApprovalStatus.rejected => 'Rejected by ${rejectedBy ?? 'Reviewer'}',
    EventApprovalStatus.completed => 'Completed',
  };

  EventItem({
    this.remoteId,
    required this.title,
    required this.org,
    required this.date,
    required this.budget,
    this.status = EventApprovalStatus.pendingAdviser,
    this.rejectedBy,
    this.adviserApprovalNote,
    this.adminApprovalNote,
    this.schoolYear,
    this.semester,
    this.eventScope,
    this.proposedBy,
  });
}

enum NotifDestination { none, inventory, events, dashboard }

class AppNotification {
  final IconData icon;
  final Color tagColor;
  final String title;
  final String body;
  final String time;
  bool unread;
  final NotifDestination destination;
  final Set<UserRole> targetRoles;

  AppNotification({
    required this.icon,
    required this.tagColor,
    required this.title,
    required this.body,
    required this.time,
    this.unread = true,
    this.destination = NotifDestination.none,
    this.targetRoles = const {},
  });
}

/// Demo/pitch feature: shows how SmartEvent could scale campus-wide.
/// Real implementation would need separate data per department — this
/// is a visual-only suggestion for the defense panel.
enum Department { systemWide, cite, cithm, cbea, camp, case_ }

extension DepartmentInfo on Department {
  String get label => switch (this) {
    Department.systemWide => 'All Departments',
    Department.cite => 'CITE',
    Department.cithm => 'CITHM',
    Department.cbea => 'CBEA',
    Department.camp => 'CAMP',
    Department.case_ => 'CASE',
  };

  String get fullName => switch (this) {
    Department.systemWide => 'University-wide (System)',
    Department.cite => 'College of Information Technology',
    Department.cithm => 'College of Hospitality Management',
    Department.cbea => 'College of Business & Accountancy',
    Department.camp => 'College of Allied Medical Personnel',
    Department.case_ => 'College of Arts, Sciences & Education',
  };

  Color get color => switch (this) {
    Department.systemWide => const Color(0xFF2B3A67), // existing indigo
    Department.cite => const Color(0xFFC17A3D), // muted orange
    Department.cithm => const Color(0xFF8A9A5B), // muted lime green
    Department.cbea => const Color(0xFFC9A227), // muted yellow/mustard
    Department.camp => const Color(0xFF4C7A52), // muted forest green
    Department.case_ => const Color(0xFF4A8FA0), // muted cyan blue
  };
}

class Account {
  /// Backend user id. Needed for the self-review guard: nobody may approve
  /// or reject a proposal they made themselves.
  final String? id;

  String name;
  String email;
  UserRole role;

  /// Display-only grouping used for theming and labels. The authoritative
  /// scope is [departmentId] / [organizationId] from `/auth/me`; this enum
  /// is a local list that predates real departments and goes away once the
  /// departments module is wired.
  Department department;

  /// Real scope from `/auth/me`. Null when signed in against a backend
  /// that predates department/organization scoping.
  final String? departmentId;
  final String? organizationId;

  /// Job title (President, Secretary, …). Never affects permissions.
  final String? position;

  /// Account is suspended, or still on a temporary password. Both come
  /// from the backend and gate what the UI should offer.
  final bool isSuspended;
  final bool mustChangePassword;

  Account({
    this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department = Department.systemWide,
    this.departmentId,
    this.organizationId,
    this.position,
    this.isSuspended = false,
    this.mustChangePassword = false,
  });
}

/// Where a module's data stands right now.
///
/// [idle] and [ready] with an empty list mean different things — "not asked
/// for yet" versus "the backend really has none" — and [failed] is neither.
/// Screens that collapse all three into a blank panel are why a dead
/// backend used to look identical to an empty database.
enum LoadStatus { idle, loading, ready, failed }

/// Per-module load state, so a screen can render loading, empty, and a
/// retryable error as three distinct states.
class LoadState {
  LoadStatus status = LoadStatus.idle;

  /// User-facing reason the load failed, or null. Safe to display as text.
  String? error;

  /// The failure was an expired or revoked session, not a transient
  /// problem: retrying the same call won't help, the user must sign in
  /// again.
  bool sessionExpired = false;

  bool get isLoading => status == LoadStatus.loading;
  bool get hasFailed => status == LoadStatus.failed;

  void reset() {
    status = LoadStatus.idle;
    error = null;
    sessionExpired = false;
  }
}

/// Matches the real backend: an expense starts pending and must be
/// reviewed before it counts toward spending. Unlike events, either
/// an Adviser OR an Admin can resolve it — no two-stage sequence here.
enum ExpenseStatus { pending, approved, rejected }

class ExpenseEntry {
  String? remoteId;
  final String vendor;
  final double amount;
  final String category;
  ExpenseStatus status;
  String? reviewedBy; // 'Adviser' or 'Admin', set once resolved
  String? reviewNote;

  /// The record this was mapped from, kept whole rather than copying a
  /// dozen fields across. Detail screens read flags, OCR readings, receipt
  /// and purchase state straight off it. Null for the local seed rows.
  RemoteExpense? remote;

  ExpenseEntry({
    this.remoteId,
    required this.vendor,
    required this.amount,
    required this.category,
    this.status = ExpenseStatus.pending,
    this.reviewedBy,
    this.reviewNote,
    this.remote,
  });

  /// OCR disagreed with the confirmed total, or the backend flagged it for
  /// another reason. Either way it is shown, never hidden — and it is a
  /// prompt to look, not proof of anything.
  bool get isFlagged => remote?.isFlagged ?? false;

  String? get flagReason => remote?.flagReason;

  /// Approved and paid/received, so its asset lines are already stock.
  bool get isPurchaseCompleted => remote?.isPurchaseCompleted ?? false;

  /// Eligible for the Complete Purchase step: approved, not already
  /// completed. Whether it actually has asset lines is decided once the
  /// items are loaded.
  bool get canStartPurchaseCompletion =>
      status == ExpenseStatus.approved && !isPurchaseCompleted;
}

class AppState extends ChangeNotifier {
  /// Turns anything thrown by the API layer into one user-facing message,
  /// keeping the three cases distinct on purpose:
  ///
  ///  * [ApiException] — the backend answered and refused. Its own `detail`
  ///    is the most accurate explanation available, so it wins.
  ///  * [NetworkException] — the backend was never reached. A different
  ///    problem with a different fix, and for a write it is genuinely
  ///    unknown whether the server acted on it.
  ///  * anything else — our own code mishandled the response. Saying so is
  ///    more useful than blaming the user's connection, which is what the
  ///    old blanket `catch (_)` did.
  String _messageForFailure(Object error) {
    if (error is ApiException) return error.message;
    if (error is NetworkException) return error.message;
    return 'Unexpected problem handling the server response: $error';
  }

  /// Runs a module load, recording loading/ready/failed instead of
  /// discarding the outcome.
  Future<void> _runLoad(LoadState state, Future<void> Function() load) async {
    state
      ..status = LoadStatus.loading
      ..error = null
      ..sessionExpired = false;
    notifyListeners();

    try {
      await load();
      state.status = LoadStatus.ready;
    } catch (error) {
      state
        ..status = LoadStatus.failed
        ..error = _messageForFailure(error)
        ..sessionExpired = error is ApiException && error.isUnauthorized;
    }
    notifyListeners();
  }

  // ---- Administration ----------------------------------------------------

  late final AdminService _adminService = AdminService(_apiClient);

  List<RosterEntry> roster = [];
  final LoadState rosterLoad = LoadState();

  List<ManagedUser> managedUsers = [];
  final LoadState usersLoad = LoadState();

  List<AuditEntry> auditLog = [];
  final LoadState auditLoad = LoadState();

  Future<void> loadRoster() => _runLoad(rosterLoad, () async {
        roster = await _adminService.roster();
      });

  Future<void> loadManagedUsers() => _runLoad(usersLoad, () async {
        managedUsers = await _adminService.users();
      });

  Future<void> loadAuditLog() => _runLoad(auditLoad, () async {
        auditLog = await _adminService.auditLog();
      });

  /// Roster entries nobody has registered against yet — the only ones that
  /// can still be edited freely or removed.
  List<RosterEntry> get unclaimedRoster =>
      roster.where((r) => !r.isClaimed).toList();

  Future<String?> addRosterEntry({
    required String fullName,
    required String email,
    required UserRole role,
    String? position,
    String? departmentId,
    String? organizationId,
  }) async {
    try {
      final created = await _adminService.addToRoster(
        fullName: fullName,
        email: email,
        role: role,
        position: position,
        departmentId: departmentId,
        organizationId: organizationId,
      );
      roster = [created, ...roster];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> updateRosterEntry(
    RosterEntry entry, {
    UserRole? role,
    String? position,
    String? organizationId,
  }) async {
    try {
      final updated = await _adminService.updateRosterEntry(
        entry.id,
        role: role,
        position: position,
        organizationId: organizationId,
      );
      roster = [
        for (final r in roster) if (r.id == updated.id) updated else r,
      ];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> removeRosterEntry(RosterEntry entry) async {
    if (entry.isClaimed) {
      return 'That entry has already been claimed. Manage the account it '
          'created instead.';
    }
    try {
      await _adminService.removeRosterEntry(entry.id);
      roster = roster.where((r) => r.id != entry.id).toList();
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Suspends or restores an account. There is no delete — suspension
  /// revokes access while preserving everything the account did.
  Future<String?> setUserSuspended(ManagedUser user, bool suspended) async {
    if (user.id == currentAccount?.id) {
      return 'You cannot change your own access.';
    }
    try {
      final updated =
          await _adminService.updateAccess(user.id, isSuspended: suspended);
      _replaceUser(updated);
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> updateUserAccess(
    ManagedUser user, {
    UserRole? role,
    String? position,
    String? organizationId,
  }) async {
    if (user.id == currentAccount?.id) {
      return 'You cannot change your own access.';
    }
    try {
      final updated = await _adminService.updateAccess(
        user.id,
        role: role,
        position: position,
        organizationId: organizationId,
      );
      _replaceUser(updated);
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> createDepartment({
    required String code,
    required String name,
    String? description,
  }) async {
    try {
      final created = await _adminService.createDepartment(
        code: code,
        name: name,
        description: description,
      );
      departments = [...departments, created];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> createOrganization({
    required String code,
    required String name,
    required String departmentId,
  }) async {
    try {
      final created = await _adminService.createOrganization(
        code: code,
        name: name,
        departmentId: departmentId,
      );
      organizations = [...organizations, created];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Creates an Admin or SDS account. Both email a temporary password, so
  /// both fail when email is not configured — the error says so.
  Future<String?> createPrivilegedAccount({
    required bool isSds,
    required String fullName,
    required String email,
    String? position,
    String? organizationId,
    String? departmentId,
  }) async {
    try {
      if (isSds) {
        await _adminService.createSdsStaff(
          fullName: fullName,
          email: email,
          position: position,
        );
      } else {
        if (organizationId == null || departmentId == null) {
          return 'An Admin needs both a department and an organization.';
        }
        await _adminService.createAdmin(
          fullName: fullName,
          email: email,
          organizationId: organizationId,
          departmentId: departmentId,
          position: position,
        );
      }
      await loadManagedUsers();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  void _replaceUser(ManagedUser updated) {
    managedUsers = [
      for (final u in managedUsers) if (u.id == updated.id) updated else u,
    ];
    notifyListeners();
  }

  // ---- Dashboard and reports ---------------------------------------------

  late final ReportsService _reportsService = ReportsService(_apiClient);

  /// The server's own dashboard figures. Null until loaded — screens must
  /// show that state rather than falling back to locally computed numbers,
  /// which would quietly disagree with the printed reports.
  DashboardSummary? dashboard;
  final LoadState dashboardLoad = LoadState();

  List<SpendingTrendPoint> spendingTrends = [];

  /// Expenses the backend flagged as worth a look. Never presented as
  /// proven wrongdoing — the route's name is not the label.
  List<RemoteExpense> flaggedExpenses = [];
  final LoadState flaggedLoad = LoadState();

  Future<void> loadDashboard() => _runLoad(dashboardLoad, () async {
        dashboard = await _reportsService.dashboard();
        spendingTrends = await _reportsService.spendingTrends();
      });

  Future<void> loadFlaggedExpenses() => _runLoad(flaggedLoad, () async {
        flaggedExpenses = await _reportsService.flagged();
      });

  /// The consolidated report currently on screen, and the filters that
  /// produced it — kept together so an export cannot be built from
  /// different ones than were displayed.
  ConsolidatedFinancialReport? financialReport;
  final LoadState financialReportLoad = LoadState();

  ReportPeriod reportPeriod = ReportPeriod.monthly;
  DateTime? reportReferenceDate;
  String? reportSchoolYear;
  Semester? reportSemester;
  EventScope? reportEventScope;

  /// Returns a message when the current filters are incomplete, or null.
  String? get reportFilterProblem => ReportsService.validateFinancialRequest(
        period: reportPeriod,
        schoolYear: reportSchoolYear,
        semester: reportSemester,
      );

  void setReportFilters({
    ReportPeriod? period,
    DateTime? referenceDate,
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
    bool clearScope = false,
  }) {
    if (period != null) reportPeriod = period;
    if (referenceDate != null) reportReferenceDate = referenceDate;
    if (schoolYear != null) reportSchoolYear = schoolYear;
    if (semester != null) reportSemester = semester;
    if (clearScope) {
      reportEventScope = null;
    } else if (eventScope != null) {
      reportEventScope = eventScope;
    }
    notifyListeners();
  }

  Future<void> loadFinancialReport() {
    return _runLoad(financialReportLoad, () async {
      final problem = reportFilterProblem;
      if (problem != null) throw ApiException(422, problem);

      financialReport = await _reportsService.financialReport(
        period: reportPeriod,
        referenceDate: reportReferenceDate,
        schoolYear: reportSchoolYear,
        semester: reportSemester,
        eventScope: reportEventScope,
      );
    });
  }

  /// Downloads the consolidated report using **the filters currently on
  /// screen**, so the file always matches what was displayed.
  Future<({DownloadedFile? file, String? error})> exportFinancialReport(
    ExportFormat format,
  ) async {
    final problem = reportFilterProblem;
    if (problem != null) return (file: null, error: problem);

    try {
      final file = await _reportsService.exportFinancial(
        period: reportPeriod,
        format: format,
        referenceDate: reportReferenceDate,
        schoolYear: reportSchoolYear,
        semester: reportSemester,
        eventScope: reportEventScope,
      );
      return (file: file, error: null);
    } catch (error) {
      return (file: null, error: _messageForFailure(error));
    }
  }

  Future<({DownloadedFile? file, String? error})> exportDashboard(
    ExportFormat format,
  ) async {
    try {
      return (file: await _reportsService.exportDashboard(format), error: null);
    } catch (error) {
      return (file: null, error: _messageForFailure(error));
    }
  }

  Future<({EventReport? report, String? error})> loadEventReport(
    String eventId,
  ) async {
    try {
      return (report: await _reportsService.eventReport(eventId), error: null);
    } catch (error) {
      return (report: null, error: _messageForFailure(error));
    }
  }

  // ---- Proposal letters --------------------------------------------------

  late final ProposalLetterService _letterService =
      ProposalLetterService(_apiClient);

  List<ProposalLetter> letters = [];
  final LoadState lettersLoad = LoadState();

  Future<void> loadLetters() => _runLoad(lettersLoad, () async {
        letters = await _letterService.list();
      });

  /// Uploads a letter. [bytes] rather than a path so this works on web too.
  Future<String?> uploadLetter({
    required String eventId,
    required String title,
    required List<int> bytes,
    required String filename,
  }) async {
    if (bytes.length > ProposalLetterService.maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      return 'That document is ${mb}MB. The limit is 10MB.';
    }
    try {
      final uploaded = await _letterService.upload(
        eventId: eventId,
        title: title,
        bytes: bytes,
        filename: filename,
      );
      letters = [uploaded, ...letters];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// The event's title, when this account can see events at all.
  ///
  /// SDS Staff never loads events — calling `/events` would 403 — so it
  /// gets null here and the UI shows the event id instead, which is what
  /// the backend returns anyway.
  String? eventTitleFor(String eventId) => events
      .where((e) => e.remoteId == eventId)
      .map((e) => e.title)
      .firstOrNull;

  // ---- Inventory ---------------------------------------------------------

  late final InventoryService _inventoryService = InventoryService(_apiClient);

  /// The catalog from the backend. Distinct from the legacy local
  /// `inventory` list, which is mock data pending removal.
  List<RemoteInventoryItem> catalog = [];
  final LoadState catalogLoad = LoadState();

  /// Server-side filters. Drafts and missing-event are the administrator's
  /// two work queues.
  bool? catalogDraftFilter;
  String? catalogEventFilter;
  bool catalogMissingEventOnly = false;

  Future<void> loadCatalog() => _runLoad(catalogLoad, () async {
        catalog = await _inventoryService.list(
          isDraft: catalogDraftFilter,
          eventId: catalogEventFilter,
          missingEvent: catalogMissingEventOnly,
        );
      });

  Future<void> applyCatalogFilter({
    bool? isDraft,
    String? eventId,
    bool missingEventOnly = false,
  }) async {
    catalogDraftFilter = isDraft;
    catalogEventFilter = eventId;
    catalogMissingEventOnly = missingEventOnly;
    notifyListeners();
    await loadCatalog();
  }

  /// Items at or below their own threshold.
  List<RemoteInventoryItem> get lowStockItems =>
      catalog.where((i) => i.isLowStock).toList();

  /// Catalog records created by purchase completion, awaiting an
  /// administrator's confirmation before they can take manual movements.
  List<RemoteInventoryItem> get draftItems =>
      catalog.where((i) => i.isDraft).toList();

  Future<({List<InventoryMovement>? movements, String? error})> loadMovements(
    RemoteInventoryItem item, {
    String? eventId,
  }) async {
    try {
      return (
        movements: await _inventoryService.movements(item.id, eventId: eventId),
        error: null,
      );
    } catch (error) {
      return (movements: null, error: _messageForFailure(error));
    }
  }

  Future<String?> createInventoryItem({
    required String eventId,
    required String itemName,
    String? description,
    int quantity = 0,
    String unit = 'pcs',
    int lowStockThreshold = 5,
    String? location,
    InitialStockType initialTransactionType = InitialStockType.openingBalance,
    String reason = 'Opening stock',
    String? departmentId,
    String? organizationId,
  }) async {
    try {
      final created = await _inventoryService.create(
        eventId: eventId,
        itemName: itemName,
        description: description,
        quantity: quantity,
        unit: unit,
        lowStockThreshold: lowStockThreshold,
        location: location,
        initialTransactionType: initialTransactionType,
        reason: reason,
        departmentId: departmentId,
        organizationId: organizationId,
      );
      catalog = [created, ...catalog];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Metadata only — quantity is not settable here by design.
  Future<String?> updateInventoryItem(
    RemoteInventoryItem item, {
    String? itemName,
    String? description,
    String? unit,
    int? lowStockThreshold,
    String? location,
    String? eventId,
  }) async {
    try {
      final updated = await _inventoryService.update(
        item.id,
        itemName: itemName,
        description: description,
        unit: unit,
        lowStockThreshold: lowStockThreshold,
        location: location,
        eventId: eventId,
      );
      _replaceCatalogItem(updated);
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> deleteInventoryItem(RemoteInventoryItem item) async {
    try {
      await _inventoryService.delete(item.id);
      catalog = catalog.where((i) => i.id != item.id).toList();
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Accepts a purchase-created draft. Adds no stock — that already
  /// happened when the purchase was completed.
  Future<String?> confirmInventoryDraft(RemoteInventoryItem item) async {
    try {
      _replaceCatalogItem(await _inventoryService.confirmDraft(item.id));
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Records a stock movement.
  ///
  /// [count] is the positive number the user typed; the sign is applied
  /// from the movement type so nobody has to reason about negatives.
  Future<String?> recordInventoryMovement(
    RemoteInventoryItem item, {
    required InventoryMovementType type,
    required String eventId,
    required String count,
    required String reason,
  }) async {
    final change = signedChangeFor(type, count);
    if (change == null) {
      return 'Enter a whole number of ${item.unit} greater than zero.';
    }
    if (reason.trim().isEmpty) return 'Give a reason for this movement.';
    if (reason.trim().length > InventoryService.maxReasonLength) {
      return 'Keep the reason under '
          '${InventoryService.maxReasonLength} characters.';
    }
    // Caught here so the user sees why rather than a constraint violation.
    if (change < 0 && item.quantity + change < 0) {
      return 'That would leave ${item.itemName} below zero — only '
          '${item.quantity} ${item.unit} are in stock.';
    }

    try {
      await _inventoryService.recordMovement(
        item.id,
        type: type,
        eventId: eventId,
        changeQty: change,
        reason: reason.trim(),
      );
      // Stock changed, so the catalog row is stale.
      _replaceCatalogItem(await _inventoryService.get(item.id));
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  void _replaceCatalogItem(RemoteInventoryItem updated) {
    catalog = [
      for (final i in catalog) if (i.id == updated.id) updated else i,
    ];
    notifyListeners();
  }

  // ---- Income ------------------------------------------------------------

  late final IncomeService _incomeService = IncomeService(_apiClient);

  List<Income> incomes = [];
  final LoadState incomesLoad = LoadState();

  /// Narrows the ledger to one event — the only server-side income filter.
  String? incomeEventFilter;

  Future<void> loadIncomes() => _runLoad(incomesLoad, () async {
        incomes = await _incomeService.list(eventId: incomeEventFilter);
      });

  Future<void> applyIncomeFilter({String? eventId}) async {
    incomeEventFilter = eventId;
    notifyListeners();
    await loadIncomes();
  }

  /// Income that counts toward totals — everything whose receipt is not
  /// pending or rejected.
  double get countedIncomeTotal => incomes
      .where((i) => !i.isWithheld)
      .fold(0.0, (sum, i) => sum + i.amount);

  /// Recorded but excluded, pending a receipt decision. Shown separately
  /// rather than folded into the total or hidden.
  double get withheldIncomeTotal =>
      incomes.where((i) => i.isWithheld).fold(0.0, (sum, i) => sum + i.amount);

  /// Totals per fund source, counted income only.
  Map<FundSource, double> get incomeBySource {
    final totals = <FundSource, double>{};
    for (final income in incomes.where((i) => !i.isWithheld)) {
      totals[income.sourceType] = (totals[income.sourceType] ?? 0) + income.amount;
    }
    return totals;
  }

  /// Records income. There is no edit or delete counterpart, by design.
  Future<String?> recordIncome({
    required String eventId,
    required String source,
    required FundSource sourceType,
    required String purpose,
    required String amount,
    DateTime? receivedOn,
    ReceiptDetailsInput? receipt,
  }) async {
    try {
      final created = await _incomeService.record(
        eventId: eventId,
        source: source,
        sourceType: sourceType,
        purpose: purpose,
        amount: amount,
        receivedOn: receivedOn,
        receipt: receipt,
      );
      incomes = [created, ...incomes];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  // ---- Receipts and duplicate review -------------------------------------

  late final ReceiptService _receiptService = ReceiptService(_apiClient);

  List<Receipt> receipts = [];
  final LoadState receiptsLoad = LoadState();

  /// Narrows to a single event, or to the pending duplicate queue. Both are
  /// server-side filters, so changing them reloads.
  String? receiptEventFilter;
  ReceiptReviewStatus? receiptStatusFilter;
  bool receiptFlaggedOnly = false;

  Future<void> loadReceipts() => _runLoad(receiptsLoad, () async {
        receipts = await _receiptService.list(
          eventId: receiptEventFilter,
          flaggedOnly: receiptFlaggedOnly,
          reviewStatus: receiptStatusFilter,
        );
      });

  Future<void> applyReceiptFilter({
    String? eventId,
    ReceiptReviewStatus? reviewStatus,
    bool flaggedOnly = false,
  }) async {
    receiptEventFilter = eventId;
    receiptStatusFilter = reviewStatus;
    receiptFlaggedOnly = flaggedOnly;
    notifyListeners();
    await loadReceipts();
  }

  /// Receipts still awaiting a duplicate decision — the review queue.
  List<Receipt> get pendingReceipts =>
      receipts.where((r) => r.isAwaitingReview).toList();

  /// The receipts a flagged one resembles, for side-by-side comparison.
  /// Only the ones in scope are returned; the rest simply aren't visible to
  /// this account and are left out rather than guessed at.
  Future<({List<Receipt> found, String? error})> loadSimilarTo(
    Receipt receipt,
  ) async {
    final found = <Receipt>[];
    for (final id in receipt.similarReceiptIds) {
      try {
        found.add(await _receiptService.get(id));
      } on ApiException catch (error) {
        // A similar receipt outside this account's scope is expected, not
        // an error worth surfacing.
        if (error.isForbidden || error.isNotFound) continue;
        return (found: found, error: error.message);
      } catch (error) {
        return (found: found, error: _messageForFailure(error));
      }
    }
    return (found: found, error: null);
  }

  /// Records or updates the receipt on a transaction.
  ///
  /// A 409 here means the backend recognised an exact duplicate and saved
  /// nothing; its message explains which.
  Future<String?> recordReceipt({
    String? expenseId,
    String? incomeId,
    required String receiptUrl,
    required String purpose,
    String? merchant,
    String? receiptNumber,
    DateTime? issuedOn,
    String? amount,
  }) async {
    try {
      final saved = await _receiptService.record(
        expenseId: expenseId,
        incomeId: incomeId,
        receiptUrl: receiptUrl,
        purpose: purpose,
        merchant: merchant,
        receiptNumber: receiptNumber,
        issuedOn: issuedOn,
        amount: amount,
      );
      receipts = [saved, ...receipts.where((r) => r.id != saved.id)];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Resolves a pending duplicate flag. Reviewer must be independent of
  /// whoever recorded it — the backend enforces that.
  Future<String?> reviewReceipt(
    Receipt receipt, {
    required ReceiptDecision decision,
    required String reason,
  }) async {
    if (reason.trim().length < ReceiptService.minReasonLength) {
      return 'Give a reason of at least '
          '${ReceiptService.minReasonLength} characters.';
    }
    try {
      final reviewed = await _receiptService.review(
        receipt.id,
        decision: decision,
        reason: reason.trim(),
      );
      receipts = [
        for (final r in receipts) if (r.id == reviewed.id) reviewed else r,
      ];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  // ---- Scope (departments and organizations) -----------------------------

  late final ScopeService _scopeService = ScopeService(_apiClient);

  List<RemoteDepartment> departments = [];
  List<RemoteOrganization> organizations = [];

  /// True when this account has to choose a scope for records it creates.
  ///
  /// A scoped user's department and organization are applied server-side
  /// from its own profile. A Super Admin belongs to neither, so the backend
  /// refuses with "department_id is required when an admin creates this
  /// record" unless one is supplied.
  bool get mustChooseScope =>
      currentRole == UserRole.superAdmin ||
      (currentAccount != null && currentAccount!.departmentId == null);

  /// Loads the lookups, but only for roles allowed to read them — calling
  /// them as a Treasurer or Officer would just collect a 403.
  Future<void> loadScopeOptions() async {
    if (!(currentRole?.isAdministrator ?? false)) return;

    try {
      departments = await _scopeService.departments();
      organizations = await _scopeService.organizations();
      notifyListeners();
    } catch (_) {
      // A missing lookup must not block the screen that needed it; the
      // form still reports the backend's own error on submit.
    }
  }

  /// Organizations belonging to [departmentId], since an organization is
  /// only valid within its own department.
  List<RemoteOrganization> organizationsIn(String? departmentId) => departmentId == null
      ? const []
      : organizations.where((o) => o.departmentId == departmentId).toList();

  final LoadState categoriesLoad = LoadState();
  final LoadState eventsLoad = LoadState();
  final LoadState expensesLoad = LoadState();

  List<LoadState> get _moduleLoads => [categoriesLoad, eventsLoad, expensesLoad];

  bool get isLoadingAnyModule => _moduleLoads.any((s) => s.isLoading);

  /// Distinct failure messages across every module, for a single summary
  /// banner or snackbar. Empty when everything loaded.
  List<String> get loadFailures =>
      _moduleLoads.where((s) => s.hasFailed).map((s) => s.error!).toSet().toList();

  /// Any module failed because the session is no longer valid.
  bool get sessionExpired => _moduleLoads.any((s) => s.sessionExpired);

  late final CategoryService _categoryService = CategoryService(_apiClient);

  /// Real categories fetched from the backend — replaces the old fixed
  /// 4-category mock. Populated after a successful real Sign In.
  List<Category> categories = [];

  Map<String, double> get categoryBudgets => {for (final c in categories) c.name: c.allocatedBudget};

  /// Server-authoritative — comes straight from the database trigger
  /// (fn_deduct_category_balance), not computed locally.
  Map<String, double> get categoryRemainingBudgets => {for (final c in categories) c.name: c.remainingBudget};

  List<String> get expenseCategories => categories.map((c) => c.name).toList();

  double get totalAllocated => categoryBudgets.values.fold(0.0, (a, b) => a + b);
  double get remainingBalance => categoryRemainingBudgets.values.fold(0.0, (a, b) => a + b);
  double get totalExpended => totalAllocated - remainingBalance;

  Future<void> loadCategories() => _runLoad(categoriesLoad, () async {
        categories = await _categoryService.list();
      });

  /// Admin/Super Admin. Returns null on success, or a message to show.
  Future<String?> createCategory({
    required String name,
    required double allocatedBudget,
    double lowBalanceThreshold = 0,
  }) async {
    try {
      final created = await _categoryService.create(
        name: name,
        allocatedBudget: allocatedBudget,
        lowBalanceThreshold: lowBalanceThreshold,
      );
      categories = [...categories, created];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Sends only the fields that changed — a PATCH is not a place to echo
  /// the whole object back, and nulls here would be read as clearing.
  ///
  /// Note that raising `allocatedBudget` does not top up the remaining
  /// balance: remaining is server-owned and only moves through the
  /// database's own deduction trigger.
  Future<String?> updateCategory(
    Category category, {
    String? name,
    double? allocatedBudget,
    double? lowBalanceThreshold,
  }) async {
    try {
      final updated = await _categoryService.update(
        category.id,
        name: name,
        allocatedBudget: allocatedBudget,
        lowBalanceThreshold: lowBalanceThreshold,
      );
      categories = [
        for (final c in categories) if (c.id == updated.id) updated else c,
      ];
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Admin/Super Admin. The backend refuses with 409 when any event or
  /// expense still references the category; that explanation comes back in
  /// the returned message rather than being guessed at here.
  Future<String?> deleteCategory(Category category) async {
    try {
      await _categoryService.delete(category.id);
      categories = categories.where((c) => c.id != category.id).toList();
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  late final EventService _eventService = EventService(_apiClient);

  EventApprovalStatus _eventStatusFromString(String status) => switch (status) {
    'draft' => EventApprovalStatus.draft,
    // Legacy 'pending' means awaiting adviser review.
    'pending' || 'pending_adviser' => EventApprovalStatus.pendingAdviser,
    'pending_admin' => EventApprovalStatus.pendingAdmin,
    'approved' => EventApprovalStatus.approved,
    'rejected' => EventApprovalStatus.rejected,
    'completed' => EventApprovalStatus.completed,
    // An unrecognized status is safest treated as a draft: it offers no
    // review actions, rather than inviting a decision on something this
    // build does not understand.
    _ => EventApprovalStatus.draft,
  };

  /// The organization's name, when this account can read the list.
  ///
  /// Only Admin and Super Admin may call `/organizations`, so for everyone
  /// else this is empty rather than a guess — an event card simply omits
  /// the line instead of claiming an organization it cannot verify.
  String _organizationNameFor(String? organizationId) {
    if (organizationId == null) return '';
    return organizations
            .where((o) => o.id == organizationId)
            .map((o) => o.name)
            .firstOrNull ??
        '';
  }

  EventItem _mapRemoteEvent(RemoteEvent remote) {
    return EventItem(
      remoteId: remote.id,
      title: remote.title,
      // The real organization, resolved from the id the backend sends.
      // Only Admin and above can read the organization list, so everyone
      // else sees nothing here rather than a guessed name.
      org: _organizationNameFor(remote.organizationId),
      date: remote.eventDate == null
          ? 'No date set'
          : '${remote.eventDate!.month}/${remote.eventDate!.day}/${remote.eventDate!.year}',
      budget: '₱${remote.allocatedBudget.toStringAsFixed(2)}',
      status: _eventStatusFromString(remote.status),
      schoolYear: remote.schoolYear,
      semester: remote.semester,
      eventScope: remote.eventScope,
      proposedBy: remote.proposedBy,
    );
  }

  /// School years the backend already has, for the list filter and the
  /// create form's picker. Merged with local suggestions at the point of
  /// use, since a new school year has to be startable before any event
  /// exists in it.
  List<String> knownSchoolYears = [];

  /// The school year the events list is filtered to, or null for all.
  /// This is a real server-side filter, unlike status and text search.
  String? schoolYearFilter;

  /// Show only events missing academic metadata — the repair queue.
  bool showOnlyMissingSchoolYear = false;

  Future<void> loadSchoolYears() async {
    try {
      knownSchoolYears = await _eventService.schoolYears();
      notifyListeners();
    } catch (_) {
      // A missing or failing picker source must not block the list; the
      // form still offers locally generated years and accepts a typed one.
    }
  }

  /// Applies a server-side filter and reloads. Passing nothing clears both.
  Future<void> applyEventFilter({
    String? schoolYear,
    bool missingOnly = false,
  }) async {
    schoolYearFilter = schoolYear;
    showOnlyMissingSchoolYear = missingOnly;
    notifyListeners();
    await loadEvents();
  }

  Future<void> loadEvents() => _runLoad(eventsLoad, () async {
        final remoteEvents = await _eventService.list(
          schoolYear: schoolYearFilter,
          missingSchoolYear: showOnlyMissingSchoolYear,
        );
        events
          ..clear()
          ..addAll(remoteEvents.map(_mapRemoteEvent));
      });

  /// Review timeline for one event: who decided what, when, and why.
  ///
  /// The backend returns reviewer IDs, not display names, and fetching
  /// `/users` from a role that isn't allowed to would just 403 — so the IDs
  /// are shown as-is until a name-display change is agreed with the backend.
  Future<({List<ApprovalRecord>? records, String? error})> loadApprovals(
    EventItem event,
  ) async {
    final remoteId = event.remoteId;
    if (remoteId == null) {
      return (records: null, error: 'This event has no backend record yet.');
    }
    try {
      return (records: await _eventService.listApprovals(remoteId), error: null);
    } catch (error) {
      return (records: null, error: _messageForFailure(error));
    }
  }

  /// Admin/Super Admin repair for legacy events with missing academic
  /// fields. It fills gaps only — it never overwrites values already set.
  Future<String?> repairEventAcademicMetadata(
    EventItem event, {
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
  }) async {
    final remoteId = event.remoteId;
    if (remoteId == null) return 'This event has no backend record yet.';

    try {
      final updated = await _eventService.repairAcademicMetadata(
        remoteId,
        schoolYear: schoolYear,
        semester: semester,
        eventScope: eventScope,
      );
      event
        ..schoolYear = updated.schoolYear
        ..semester = updated.semester
        ..eventScope = updated.eventScope;
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  late final ExpenseService _expenseService = ExpenseService(_apiClient);

  ExpenseStatus _expenseStatusFromString(String status) => switch (status) {
    'approved' => ExpenseStatus.approved,
    'rejected' => ExpenseStatus.rejected,
    _ => ExpenseStatus.pending,
  };

  /// Category name isn't on RemoteExpense directly (only category_id) —
  /// resolve it via the already-loaded categories list.
  ExpenseEntry _mapRemoteExpense(RemoteExpense remote) {
    final categoryName = categories.where((c) => c.id == remote.categoryId).firstOrNull?.name ?? 'Unknown';
    return ExpenseEntry(
      remoteId: remote.id,
      vendor: remote.description,
      amount: remote.amount,
      category: categoryName,
      status: _expenseStatusFromString(remote.status),
      remote: remote,
    );
  }

  Future<void> loadExpenses() => _runLoad(expensesLoad, () async {
        final remoteExpenses = await _expenseService.list();
        expenses
          ..clear()
          ..addAll(remoteExpenses.map(_mapRemoteExpense));
      });
  /// Admin-only. Creates the category if it doesn't exist yet by name,
  /// otherwise updates its allocated budget. Returns null on success,
  /// or an error message.
  Future<String?> setCategoryBudget(String categoryName, double amount) async {
    try {
      final existing = categories.where((c) => c.name == categoryName).firstOrNull;
      if (existing != null) {
        final updated = await _categoryService.update(existing.id, allocatedBudget: amount);
        final index = categories.indexWhere((c) => c.id == existing.id);
        categories[index] = updated;
      } else {
        final created = await _categoryService.create(name: categoryName, allocatedBudget: amount);
        categories.add(created);
      }
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

    /// Filled from the backend by loadExpenses. Empty until then, so a
  /// screen never shows invented rows that look like real spending.
  final List<ExpenseEntry> expenses = [];

  List<String> get expenseLog =>
      expenses.map((e) => '${e.vendor} · -₱${e.amount.toStringAsFixed(2)}').toList();

  /// Returns null on success, or an error message. [categoryName]
  /// must match a real category's name — resolved to its real ID here.
  // ---- Expense detail, receipts and purchase completion ------------------

  /// The itemized breakdown. Purchase completion needs these real line IDs,
  /// so they are loaded rather than reconstructed.
  Future<({List<ExpenseLine>? lines, String? error})> loadExpenseLines(
    ExpenseEntry expense,
  ) async {
    final remoteId = expense.remoteId;
    if (remoteId == null) {
      return (lines: null, error: 'This expense has no backend record yet.');
    }
    try {
      return (lines: await _expenseService.items(remoteId), error: null);
    } catch (error) {
      return (lines: null, error: _messageForFailure(error));
    }
  }

  /// The single review decision for this expense, with remarks.
  Future<({List<ApprovalRecord>? records, String? error})> loadExpenseApprovals(
    ExpenseEntry expense,
  ) async {
    final remoteId = expense.remoteId;
    if (remoteId == null) {
      return (records: null, error: 'This expense has no backend record yet.');
    }
    try {
      return (
        records: await _expenseService.listApprovals(remoteId),
        error: null,
      );
    } catch (error) {
      return (records: null, error: _messageForFailure(error));
    }
  }

  /// Reads a receipt image. **Saves nothing** — the returned values are the
  /// OCR's reading for the user to correct before an expense is created.
  Future<({ScannedReceipt? scan, String? error})> scanReceipt({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final scan = await _expenseService.scanReceipt(
        bytes: bytes,
        filename: filename,
      );
      return (scan: scan, error: null);
    } catch (error) {
      return (scan: null, error: _messageForFailure(error));
    }
  }

  /// Attaches a receipt image to an existing pending expense.
  Future<String?> uploadExpenseReceipt(
    ExpenseEntry expense, {
    required List<int> bytes,
    required String filename,
  }) async {
    final remoteId = expense.remoteId;
    if (remoteId == null) return 'This expense has no backend record yet.';

    try {
      await _expenseService.uploadReceipt(
        remoteId,
        bytes: bytes,
        filename: filename,
      );
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Records payment and delivery on an approved asset expense.
  ///
  /// This — not approval — is what adds stock, and it runs once. After it
  /// succeeds, expenses, items, inventory and the stock ledger are all
  /// stale and need reloading.
  Future<String?> completePurchase(
    ExpenseEntry expense,
    PurchaseCompletionInput completion,
  ) async {
    final remoteId = expense.remoteId;
    if (remoteId == null) return 'This expense has no backend record yet.';

    try {
      await _expenseService.completePurchase(remoteId, completion);
      await loadExpenses();
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Creates an expense with everything the contract allows: an optional
  /// event, an expense date, receipt metadata and itemized lines.
  ///
  /// [amount] and each line amount are decimal strings. Line totals may not
  /// exceed the expense total — the backend rejects that, and so should the
  /// form before getting here.
  Future<String?> createExpense({
    required String categoryId,
    String? eventId,
    required String description,
    required String amount,
    DateTime? expenseDate,
    ReceiptDetailsInput? receipt,
    List<ExpenseLineInput> items = const [],
    String? departmentId,
    String? organizationId,
  }) async {
    try {
      final created = await _expenseService.create(
        categoryId: categoryId,
        eventId: eventId,
        description: description,
        amount: amount,
        expenseDate: expenseDate,
        receipt: receipt,
        items: items,
        departmentId: departmentId,
        organizationId: organizationId,
      );
      expenses.insert(0, _mapRemoteExpense(created));
      addNotification(AppNotification(
        icon: Icons.receipt_long_outlined,
        tagColor: const Color(0xFFE8A33D),
        title: 'New expense to review',
        body: '$description (₱$amount) is awaiting review.',
        time: 'Just now',
        destination: NotifDestination.dashboard,
        targetRoles: {UserRole.adviser, UserRole.admin},
      ));
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> logExpense(String vendor, double amount, {required String categoryName}) async {
    final category = categories.where((c) => c.name == categoryName).firstOrNull;
    if (category == null) return 'Please select a valid category.';

    try {
      final created = await _expenseService.create(
        categoryId: category.id,
        description: vendor,
        // Money crosses the wire as a decimal string so it survives the
        // backend's Decimal exactly.
        amount: MoneyInput.fromDouble(amount),
      );
      expenses.insert(0, _mapRemoteExpense(created));
      addNotification(AppNotification(
        icon: Icons.receipt_long_outlined,
        tagColor: const Color(0xFFE8A33D),
        title: 'New expense to review',
        body: '$vendor (₱${amount.toStringAsFixed(2)}) is awaiting review.',
        time: 'Just now',
        destination: NotifDestination.dashboard,
        targetRoles: {UserRole.adviser, UserRole.admin},
      ));
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  List<ExpenseEntry> get pendingExpenses =>
      expenses.where((e) => e.status == ExpenseStatus.pending).toList();

  /// Category -> total spent, computed ONLY from approved expenses —
  /// matching the real backend, where budget only deducts on approval.
  Map<String, double> get spendByCategory {
    final totals = {for (final c in expenseCategories) c: 0.0};
    for (final e in expenses.where((e) => e.status == ExpenseStatus.approved)) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return totals;
  }

  /// Returns null on success, or an error message — including the
  /// real budget-guard block, now enforced server-side (and checked
  /// against BOTH the category and the linked event's budget, if any).
  Future<String?> approveExpense(ExpenseEntry expense, {required String reviewerRole, String? note}) async {
    if (expense.remoteId == null) return 'This expense has no real backend record yet.';
    try {
      // The reviewer's note is part of the decision record, so it goes to
      // the backend rather than only being kept on the local object.
      final updated = await _expenseService.approve(
        expense.remoteId!,
        remarks: (note?.isEmpty ?? true) ? null : note,
      );
      expense.status = _expenseStatusFromString(updated.status);
      expense.reviewedBy = reviewerRole;
      expense.reviewNote = note;
      addNotification(AppNotification(
        icon: Icons.check_circle_outline,
        tagColor: const Color(0xFF3F8272),
        title: 'Expense approved: ${expense.vendor}',
        body: '₱${expense.amount.toStringAsFixed(2)} approved by $reviewerRole.',
        time: 'Just now',
        destination: NotifDestination.dashboard,
        targetRoles: {UserRole.officer},
      ));
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      // A refusal here is usually the budget guard or a receipt-review
      // block, which an Admin needs to see rather than only the reviewer
      // who happened to click Approve.
      addNotification(AppNotification(
        icon: Icons.warning_amber_rounded,
        tagColor: const Color(0xFFC1503D),
        title: 'Blocked: ${expense.vendor}',
        body: error.message,
        time: 'Just now',
        destination: NotifDestination.dashboard,
        targetRoles: {UserRole.admin},
      ));
      notifyListeners();
      return error.message;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> rejectExpense(ExpenseEntry expense, {required String reviewerRole, String? note}) async {
    if (expense.remoteId == null) return 'This expense has no real backend record yet.';
    try {
      final updated = await _expenseService.reject(
        expense.remoteId!,
        remarks: (note?.isEmpty ?? true) ? null : note,
      );
      expense.status = _expenseStatusFromString(updated.status);
      expense.reviewedBy = reviewerRole;
      expense.reviewNote = note;
      addNotification(AppNotification(
        icon: Icons.cancel_outlined,
        tagColor: const Color(0xFFC1503D),
        title: 'Expense rejected: ${expense.vendor}',
        body: note?.isNotEmpty == true ? note! : 'No reason given.',
        time: 'Just now',
        destination: NotifDestination.dashboard,
        targetRoles: {UserRole.officer},
      ));
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

    /// Filled from the backend by loadEvents.
  final List<EventItem> events = [];

  /// Returns null on success, or an error message. Creates a real
  /// backend event (draft), then submits it — the server itself
  /// decides which stage it lands on based on who's signed in
  /// (matching the two-stage design), so we don't need to compute
  /// that locally anymore.
  /// Creates a proposal and submits it in one step.
  ///
  /// Pass [submitNow] false to leave it as a draft the proposer can come
  /// back to. School year, semester and scope are required by the backend
  /// on new events.
  Future<String?> addEvent({
    required String title,
    String? categoryId,
    required double estimatedCost,
    DateTime? eventDate,
    String? description,
    required String schoolYear,
    required Semester semester,
    required EventScope eventScope,
    bool submitNow = true,
    String? departmentId,
    String? organizationId,
  }) async {
    try {
      final created = await _eventService.create(
        categoryId: categoryId,
        title: title,
        description: description,
        eventDate: eventDate,
        estimatedCost: estimatedCost,
        allocatedBudget: estimatedCost,
        status: 'draft',
        schoolYear: schoolYear,
        semester: semester,
        eventScope: eventScope,
        // Scoped accounts get these from their own profile; a Super Admin
        // belongs to no department and has to say which one this is for.
        departmentId: departmentId,
        organizationId: organizationId,
      );
      final submitted =
          submitNow ? await _eventService.submit(created.id) : created;

      final mapped = _mapRemoteEvent(submitted);
      events.insert(0, mapped);

      switch (mapped.status) {
        case EventApprovalStatus.pendingAdviser:
          addNotification(AppNotification(
            icon: Icons.event_outlined,
            tagColor: const Color(0xFFE8A33D),
            title: 'New proposal to review',
            body: '${mapped.title} is awaiting your review.',
            time: 'Just now',
            destination: NotifDestination.events,
            targetRoles: {UserRole.adviser},
          ));
          break;
        case EventApprovalStatus.pendingAdmin:
          addNotification(AppNotification(
            icon: Icons.event_outlined,
            tagColor: const Color(0xFFE8A33D),
            title: 'New proposal to approve',
            body: '${mapped.title} is awaiting your final approval.',
            time: 'Just now',
            destination: NotifDestination.events,
            targetRoles: {UserRole.admin},
          ));
          break;
        // No proposal is auto-approved, not even an administrator's own:
        // it still needs an independent adviser and a second
        // Admin/Super Admin. So none of the remaining statuses is a
        // just-submitted outcome worth announcing here.
        case EventApprovalStatus.draft:
        case EventApprovalStatus.approved:
        case EventApprovalStatus.rejected:
        case EventApprovalStatus.completed:
          break;
      }

      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  void updateEvent() {
    notifyListeners();
  }

  /// Returns null on success, or an error message. Matches the
  /// backend's real Edit Proposal flow: PATCH the edited fields, then
  /// submit() to actually transition the status server-side.
  Future<String?> resubmitEvent(
      EventItem event, {
        required String title,
        String? description,
        DateTime? eventDate,
        double? estimatedCost,
        double? allocatedBudget,
        String? schoolYear,
        Semester? semester,
        EventScope? eventScope,
      }) async {
    if (event.remoteId == null) return 'This event has no real backend record yet.';
    try {
      await _eventService.update(
        event.remoteId!,
        title: title,
        description: description,
        eventDate: eventDate,
        estimatedCost: estimatedCost,
        allocatedBudget: allocatedBudget,
        schoolYear: schoolYear,
        semester: semester,
        eventScope: eventScope,
      );
      final submitted = await _eventService.submit(event.remoteId!);

      event.title = submitted.title;
      event.status = _eventStatusFromString(submitted.status);
      event.rejectedBy = null;
      event.adviserApprovalNote = null;
      event.adminApprovalNote = null;

      addNotification(AppNotification(
        icon: Icons.autorenew,
        tagColor: const Color(0xFFE8A33D),
        title: 'Event revised: ${event.title}',
        body: 'The officer made changes and resubmitted this proposal for review.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.adviser},
      ));
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  List<EventItem> get pendingAdviserEvents =>
      events.where((e) => e.status == EventApprovalStatus.pendingAdviser).toList();

  List<EventItem> get pendingAdminEvents =>
      events.where((e) => e.status == EventApprovalStatus.pendingAdmin).toList();

  List<EventItem> get adviserHandledEvents => events
      .where((e) =>
  e.adviserApprovalNote != null ||
      e.status == EventApprovalStatus.pendingAdmin ||
      e.status == EventApprovalStatus.approved ||
      (e.status == EventApprovalStatus.rejected && e.rejectedBy == 'Adviser'))
      .toList();

  List<EventItem> get adminHandledEvents => events
      .where((e) =>
  e.status == EventApprovalStatus.approved ||
      (e.status == EventApprovalStatus.rejected && e.rejectedBy == 'Admin'))
      .toList();

  /// Returns null on success, or an error message.
  Future<String?> adviserDecision(EventItem event, {required bool approved, String? note}) async {
    if (event.remoteId == null) return 'This event has no real backend record yet.';
    try {
      final RemoteEvent updated = approved
          ? await _eventService.approve(event.remoteId!, remarks: note)
          : await _eventService.reject(event.remoteId!, remarks: note);

      event.status = _eventStatusFromString(updated.status);
      event.adviserApprovalNote = note;
      if (!approved) event.rejectedBy = 'Adviser';

      addNotification(approved
          ? AppNotification(
        icon: Icons.fact_check_outlined,
        tagColor: const Color(0xFFE8A33D),
        title: 'Advanced to Admin: ${event.title}',
        body: 'Approved by adviser, now awaiting final admin approval.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.admin, UserRole.officer},
      )
          : AppNotification(
        icon: Icons.cancel_outlined,
        tagColor: const Color(0xFFC1503D),
        title: 'Rejected by Adviser: ${event.title}',
        body: note?.isNotEmpty == true ? note! : 'No reason given.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.officer},
      ));
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Returns null on success, or an error message.
  Future<String?> adminDecision(EventItem event, {required bool approved, String? note}) async {
    if (event.remoteId == null) return 'This event has no real backend record yet.';
    try {
      final RemoteEvent updated = approved
          ? await _eventService.approve(event.remoteId!, remarks: note)
          : await _eventService.reject(event.remoteId!, remarks: note);

      event.status = _eventStatusFromString(updated.status);
      event.adminApprovalNote = note;
      if (!approved) event.rejectedBy = 'Admin';

      addNotification(approved
          ? AppNotification(
        icon: Icons.check_circle_outline,
        tagColor: const Color(0xFF3F8272),
        title: 'Approved: ${event.title}',
        body: 'Final approval granted. Event is now active.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.officer, UserRole.adviser},
      )
          : AppNotification(
        icon: Icons.cancel_outlined,
        tagColor: const Color(0xFFC1503D),
        title: 'Rejected by Admin: ${event.title}',
        body: note?.isNotEmpty == true ? note! : 'No reason given.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.officer, UserRole.adviser},
      ));
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

    /// In-app notices raised by this session's own actions. The backend
  /// has a /notifications endpoint that is not wired up yet, so nothing
  /// here survives a restart — but nothing here is invented either.
  final List<AppNotification> notifications = [];

  void addNotification(AppNotification n) {
    notifications.insert(0, n);
  }

  List<AppNotification> notificationsFor(UserRole? role) {
    return notifications
        .where((n) => n.targetRoles.isEmpty || (role != null && n.targetRoles.contains(role)))
        .toList();
  }

  int unreadCountFor(UserRole? role) => notificationsFor(role).where((n) => n.unread).length;

  void markAllNotificationsReadFor(UserRole? role) {
    for (final n in notificationsFor(role)) {
      n.unread = false;
    }
    notifyListeners();
  }

  void markRead(AppNotification n) {
    n.unread = false;
    notifyListeners();
  }

    /// Only used by the dev quick-login shortcut.
  final List<Account> _accounts = [];

  Account? currentAccount;
  UserRole? currentRole;

  final ApiClient _apiClient = ApiClient();
  late final AuthService _authService = AuthService(_apiClient);

  /// Thrown when `/auth/me` reports a role this build doesn't know. Better
  /// than guessing a permission set for an account the app can't model.
  static const String _unknownRoleMessage =
      'This account has a role this version of the app does not support. '
      'Update the app, or contact your administrator.';

  // ---- Registration, verification and password flows ---------------------

  /// Roster-based self-registration (`POST /auth/register`).
  ///
  /// The email must already exist on the approved roster; the backend takes
  /// the name, role and scope from that entry, which is what prevents
  /// someone assigning themselves a role. The account is inactive until the
  /// OTP is verified, so the caller must go to Verify Email next — never to
  /// an operational screen.
  Future<String?> register({
    required String email,
    required String password,
  }) async {
    try {
      await _authService.register(email: email, password: password);
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Verifies the registration OTP and activates the account.
  ///
  /// Returns a [RegistrationResult] on success. Activation and confirmation
  /// email are separate outcomes: check `confirmationEmailFailed` and
  /// mention it, but never present it as a failed registration.
  Future<({RegistrationResult? result, String? error})> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    try {
      final result = await _authService.verifyOtp(email: email, otpCode: otpCode);
      return (result: result, error: null);
    } catch (error) {
      return (result: null, error: _messageForFailure(error));
    }
  }

  Future<String?> resendOtp({required String email}) async {
    try {
      await _authService.resendOtp(email: email);
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Requests a reset code. The backend answers the same way whether or not
  /// the address exists, so the UI must not infer anything from success.
  Future<String?> forgotPassword({required String email}) async {
    try {
      await _authService.forgotPassword(email: email);
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  Future<String?> resetPassword({
    required String email,
    required String otpCode,
    required String newPassword,
  }) async {
    try {
      await _authService.resetPassword(
        email: email,
        otpCode: otpCode,
        newPassword: newPassword,
      );
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// Changes the password, and clears the mandatory-setup flag when the
  /// backend reports it satisfied. Used both for a voluntary change and for
  /// the forced first-login setup.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      // This route is reachable on a temporary password, and it returns the
      // profile — so it is also how a setup-blocked account first learns
      // who it is.
      final profile = await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      _passwordSetupRequired = false;
      final problem = _applyProfile(profile);
      if (problem != null) return problem;

      // Only now is the account allowed to read anything else.
      if (!mustSetPassword) await _loadSignedInData();
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }

  /// True when the backend refused `/auth/me` because the account is still
  /// on a temporary password.
  ///
  /// This is not a detail of the profile, because the profile cannot be
  /// fetched at all in that state: `/auth/me` is behind
  /// `require_active_account`, which rejects temporary-password accounts
  /// with a 403. Only `/auth/change-password` is reachable. So the flag has
  /// to be inferred from that refusal and held separately.
  bool _passwordSetupRequired = false;

  /// The signed-in account must set a real password before reaching any
  /// operational screen — either because the profile says so, or because
  /// the profile itself was refused for that reason.
  bool get mustSetPassword =>
      _passwordSetupRequired || (currentAccount?.mustChangePassword ?? false);

  /// The 403 that means "set your password first" rather than "you are not
  /// allowed". The backend distinguishes them only by message, so this
  /// matches on it — and errs toward the suspension reading, which simply
  /// shows the error rather than sending the user into a setup flow they
  /// cannot complete.
  bool _isPasswordSetupRefusal(Object error) =>
      error is ApiException &&
      error.isForbidden &&
      error.message.toLowerCase().contains('password change required');

  /// The account has been suspended by an administrator. The API enforces
  /// this on every request regardless; this just lets the UI explain it.
  bool get isSuspended => currentAccount?.isSuspended ?? false;

  /// Whether a stored-session check has finished, whatever its outcome.
  /// The startup gate waits on this so the app doesn't flash the welcome
  /// screen at someone who is already signed in.
  bool sessionChecked = false;

  /// Bridges `/auth/me` into the local account model.
  ///
  /// Returns an error message when the role is unrecognized, so the caller
  /// can refuse the sign-in instead of proceeding with a guessed one.
  String? _applyProfile(UserProfile profile) {
    final role = userRoleFromWire(profile.role);
    if (role == null) return _unknownRoleMessage;

    currentAccount = Account(
      id: profile.id,
      name: profile.fullName,
      email: profile.email,
      role: role,
      departmentId: profile.departmentId,
      organizationId: profile.organizationId,
      position: profile.position,
      isSuspended: profile.isSuspended,
      mustChangePassword: profile.mustChangePassword,
    );
    currentRole = role;
    return null;
  }

  /// Categories first: expense rows resolve their category name against
  /// the loaded category list, so loading them in the other order would
  /// label every expense "Unknown".
  Future<void> _loadSignedInData() async {
    // SDS Staff is restricted to proposal letters. Calling the operational
    // endpoints would just collect 403s and surface them as failures on
    // screens that role is never meant to see.
    // Temporary-password accounts are restricted server-side until they set
    // a real one, so these calls would only collect 403s.
    if (mustSetPassword) return;

    // SDS Staff reaches proposal letters and nothing else. Loading the
    // operational modules would just collect 403s on screens that role
    // never sees.
    if (currentRole?.hasOperationalAccess != true) {
      if (currentRole?.canAccessProposalLetters ?? false) await loadLetters();
      return;
    }

    await loadCategories();
    await loadEvents();
    await loadExpenses();
    await loadSchoolYears();
    await loadScopeOptions();
    await loadDashboard();
    // Officers have no letter access at all, so this is gated too.
    if (currentRole?.canAccessProposalLetters ?? false) await loadLetters();
  }

  /// Picks up a token kept in secure storage by an earlier run.
  ///
  /// A stored token is not proof of a live session — it may have expired,
  /// or the account may have been suspended since — so `GET /auth/me` is
  /// what actually decides. Called once at startup.
  Future<void> restoreSession() async {
    try {
      final token = await _apiClient.restoreToken();
      if (token == null) return;

      final UserProfile profile;
      try {
        profile = await _authService.getCurrentUser();
      } catch (error) {
        // Same as sign-in: a stored token for an account that still owes a
        // password change is valid, it just cannot read its profile yet.
        if (_isPasswordSetupRefusal(error)) {
          _passwordSetupRequired = true;
          return;
        }
        rethrow;
      }

      if (_applyProfile(profile) != null) {
        // Role this build can't model — don't restore into a guessed
        // permission set.
        await _apiClient.setToken(null);
        return;
      }
      await _loadSignedInData();
    } on ApiException {
      // Expired, revoked, or the account is suspended. The token is dead
      // weight now, so drop it and let the user sign in again.
      await _apiClient.setToken(null);
    } on NetworkException {
      // Offline at launch. The token may still be perfectly good once
      // there's a network, so keep it stored and just show sign-in.
    } catch (_) {
      // Malformed stored value or an unreadable profile response. Don't
      // let a bad token wedge startup.
      await _apiClient.setToken(null);
    } finally {
      sessionChecked = true;
      notifyListeners();
    }
  }

  /// REAL backend call: logs in, then fetches the signed-in user's
  /// profile (login alone doesn't return it). On success, bridges the
  /// result into the existing local Account/UserRole model so the rest
  /// of the app keeps working unchanged.
  ///
  /// Returns null when authentication succeeded. The follow-up data loads
  /// are deliberately not allowed to fail the sign-in: being signed in and
  /// having the dashboard's data are separate things, and their outcome is
  /// reported through [loadFailures] instead.
  Future<String?> signIn({required String email, required String password}) async {
    try {
      await _authService.login(email: email, password: password);

      final UserProfile profile;
      try {
        profile = await _authService.getCurrentUser();
      } catch (error) {
        // A temporary-password account authenticates fine but cannot read
        // its own profile until the password is set. That is a successful
        // sign-in that routes to password setup, not a failure.
        if (_isPasswordSetupRefusal(error)) {
          _passwordSetupRequired = true;
          notifyListeners();
          return null;
        }
        rethrow;
      }

      _passwordSetupRequired = false;
      final roleProblem = _applyProfile(profile);
      if (roleProblem != null) {
        await _apiClient.setToken(null);
        return roleProblem;
      }

      // SDS Staff and Officers still sign in; what they may reach is
      // decided by role capabilities, not by blocking authentication.
      await _loadSignedInData();
      notifyListeners();
      return null;
    } catch (error) {
      return _messageForFailure(error);
    }
  }
  /// pang shortcut sa login kasi tinatamad na ko mag type all the time
  void devQuickLogin(UserRole role) {
    final testEmail = 'test.${role.name}@dev.local';
    var account = _accounts.where((a) => a.email == testEmail).firstOrNull;
    account ??= Account(
      name: 'Test ${role.label}',
      email: testEmail,
      role: role,
    );
    if (!_accounts.contains(account)) _accounts.add(account);
    currentAccount = account;
    currentRole = role;
    notifyListeners();
  }

  void updateProfile({required String name, required String email, Department? department}) {
    if (currentAccount == null) return;
    currentAccount!.name = name;
    currentAccount!.email = email;
    if (department != null) currentAccount!.department = department;
    notifyListeners();
  }

  Color get themeColor => currentAccount?.department.color ?? Department.systemWide.color;

  /// Clears the session and every record loaded for that user, so the next
  /// account signing in on this device can never see the previous one's
  /// data. There is no backend logout endpoint — the JWT simply stops
  /// being held.
  ///
  /// `inventory` and `notifications` are still local mock lists rather than
  /// user-scoped backend data, so they are left alone here; they get
  /// cleared once those modules are actually wired.
  Future<void> signOut() async {
    currentAccount = null;
    currentRole = null;
    _passwordSetupRequired = false;
    categories = [];
    events.clear();
    expenses.clear();
    for (final state in _moduleLoads) {
      state.reset();
    }
    notifyListeners();
    await _authService.logout();
  }
}