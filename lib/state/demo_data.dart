import '../api/models/academic.dart';
import 'app_state.dart';

/// A whole app's worth of data, with no server behind it.
///
/// The existing quick-login fakes a session and then lets the app call a
/// backend it has no token for, so every screen fills with 401s. That is
/// useful at a desk and useless in front of anyone. This fills the
/// collections instead and tells the app not to fetch, so every screen
/// has something true to show.
///
/// The figures are CITE's real ones from this school year, so what the
/// screens add up to is recognisable rather than arbitrary.
abstract final class DemoData {
  /// One fixed date for every audit field, so two runs of the demo show
  /// the same thing.
  static final DateTime _seedDate = DateTime(2026, 9, 1);

  /// Who you are while exploring. Treasurer by default: it is the role
  /// that can see the most without being an administrator, so the fewest
  /// screens are empty.
  static Account account(UserRole role) => Account(
    id: 'demo-account',
    name: switch (role) {
      UserRole.sdsStaff => 'Demo SDS Staff',
      UserRole.adviser => 'Demo Adviser',
      UserRole.treasurer => 'Demo Treasurer',
      _ => 'Demo Account',
    },
    email: 'demo@lcup.edu.ph',
    role: role,
    departmentId: 'demo-cite',
    organizationId: 'demo-acpes',
    position: switch (role) {
      UserRole.treasurer => 'ACPES Treasurer',
      UserRole.adviser => 'ACPES Moderator',
      UserRole.sdsStaff => 'SDS Office',
      _ => null,
    },
    isSuspended: false,
    mustChangePassword: false,
  );

  static List<Category> categories() => [
    Category(
      id: 'demo-cat-1',
      name: 'Speakers and honoraria',
      allocatedBudget: 18000,
      remainingBudget: 11000,
      lowBalanceThreshold: 2000,
      createdBy: 'demo-account',
      createdAt: _seedDate,
      updatedAt: _seedDate,
    ),
    Category(
      id: 'demo-cat-2',
      name: 'Materials and supplies',
      allocatedBudget: 12000,
      remainingBudget: 7400,
      lowBalanceThreshold: 2000,
      createdBy: 'demo-account',
      createdAt: _seedDate,
      updatedAt: _seedDate,
    ),
    Category(
      id: 'demo-cat-3',
      name: 'Food and refreshments',
      allocatedBudget: 14000,
      remainingBudget: 14000,
      lowBalanceThreshold: 2000,
      createdBy: 'demo-account',
      createdAt: _seedDate,
      updatedAt: _seedDate,
    ),
    Category(
      id: 'demo-cat-4',
      name: 'Certificates and tokens',
      allocatedBudget: 6000,
      remainingBudget: 3150,
      lowBalanceThreshold: 2000,
      createdBy: 'demo-account',
      createdAt: _seedDate,
      updatedAt: _seedDate,
    ),
  ];

  /// One of each state, so every filter on the events screen has
  /// something in it and the dashboard's progress bars show all four
  /// colours.
  static List<EventItem> events() => [
    EventItem(
      remoteId: 'demo-ev-1',
      title: 'HACK THE FUTURE: Cybersecurity and Ethical Hacking',
      org: 'ACPES',
      date: '28 Oct 2026',
      on: DateTime(2026, 10, 28),
      budget: '2500',
      status: EventApprovalStatus.pendingAdviser,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.organizational,
      proposedBy: 'demo-account',
    ),
    EventItem(
      remoteId: 'demo-ev-2',
      title: 'CITE Week: Opening Ceremony',
      org: 'CITE',
      date: '20 Oct 2026',
      on: DateTime(2026, 10, 20),
      budget: '12000',
      status: EventApprovalStatus.approved,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.departmental,
      proposedBy: 'demo-account',
    ),
    EventItem(
      remoteId: 'demo-ev-3',
      title: 'Industry Immersion Talk',
      org: 'ACPES',
      date: '5 Nov 2026',
      on: DateTime(2026, 11, 5),
      budget: '8000',
      status: EventApprovalStatus.rejected,
      rejectedBy: 'Engr. Aileen M. Habaradas',
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.organizational,
      proposedBy: 'demo-account',
    ),
    EventItem(
      remoteId: 'demo-ev-4',
      title: 'Programming Bootcamp for Freshmen',
      org: 'ACPES',
      date: '3 Dec 2026',
      on: DateTime(2026, 12, 3),
      budget: '3500',
      status: EventApprovalStatus.draft,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.departmental,
      proposedBy: 'demo-account',
    ),
    EventItem(
      remoteId: 'demo-ev-5',
      title: 'Capstone Project Exhibit',
      org: 'CITE',
      date: '9 Oct 2026',
      on: DateTime(2026, 10, 9),
      budget: '22000',
      status: EventApprovalStatus.completed,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.departmental,
      proposedBy: 'demo-account',
    ),
  ];

  /// Enough spending to make the budget figures move, including one
  /// flagged row so that screen is not empty either.
  static List<ExpenseEntry> expenses() => [
    ExpenseEntry(
      remoteId: 'demo-ex-1',
      vendor: 'Speaker honorarium — Hack the Future',
      amount: 2000,
      category: 'Speakers and honoraria',
      status: ExpenseStatus.approved,
      reviewedBy: 'Demo Adviser',
    ),
    ExpenseEntry(
      remoteId: 'demo-ex-2',
      vendor: 'National Book Store',
      amount: 1850,
      category: 'Materials and supplies',
      status: ExpenseStatus.approved,
      reviewedBy: 'Demo Adviser',
    ),
    ExpenseEntry(
      remoteId: 'demo-ex-3',
      vendor: 'Certificate printing',
      amount: 2850,
      category: 'Certificates and tokens',
      status: ExpenseStatus.pending,
    ),
    ExpenseEntry(
      remoteId: 'demo-ex-4',
      vendor: 'PrintHub — tarpaulin',
      amount: 4600,
      category: 'Materials and supplies',
      status: ExpenseStatus.rejected,
      reviewedBy: 'Demo Adviser',
      reviewNote: 'No quotation attached.',
    ),
  ];

  static List<AppNotice> notices() => [
    AppNotice(
      id: 'demo-n-1',
      kind: 'sap_cleared',
      emailStatus: 'sent',
      title: 'SDS Office approved your proposal',
      body:
          'HACK THE FUTURE has cleared Part 4. Print the form and collect '
          'the nine signatures.',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      readAt: null,
    ),
    AppNotice(
      id: 'demo-n-2',
      kind: 'event_returned',
      emailStatus: 'sent',
      title: 'Returned for revision',
      body:
          'Industry Immersion Talk: move it to the afternoon if there are '
          'affected classes in the morning.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      readAt: null,
    ),
    AppNotice(
      id: 'demo-n-3',
      kind: 'expense_approved',
      emailStatus: 'sent',
      title: 'Expense approved',
      body: 'Speaker honorarium, ₱2,000.00.',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      readAt: null,
    ),
  ];
}
