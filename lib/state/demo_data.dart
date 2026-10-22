import '../api/models/academic.dart';
import '../api/models/scope.dart';
import '../api/models/sap_proposal.dart';
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

  /// The two societies CITE actually has, and the college they sit in.
  ///
  /// Which organization an event belongs to follows the account rather
  /// than being picked per event: a JPSSITE officer proposes for
  /// JPSSITE. The demo account is an ACPES one, so its forms fill in
  /// ACPES.
  static List<RemoteDepartment> departments() => [
    RemoteDepartment(
      id: 'demo-cite',
      code: 'CITE',
      name: 'College of Information Technology and Engineering',
      description: null,
    ),
  ];

  static List<RemoteOrganization> organizations() => [
    RemoteOrganization(
      id: 'demo-acpes',
      code: 'ACPES',
      name: 'Association of Computer Engineering Students',
      departmentId: 'demo-cite',
    ),
    RemoteOrganization(
      id: 'demo-jpssite',
      code: 'JPSSITE',
      name:
          'Junior Philippine Student Society for Information Technology',
      departmentId: 'demo-cite',
    ),
  ];

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

/// Proposal content for the seeded events.
///
/// The demo had events but nothing on their proposal forms, so the SDS
/// Office opened a summary of an untitled activity with nothing in it.
/// These fill the parts a reader needs to decide: what it is, when and
/// where, what it costs and what it needs.
abstract final class DemoProposals {
  /// Everything the summary reads, for one seeded event. Null for an
  /// event this demo has written nothing for.
  static SapDetails? detailsFor(EventItem event) {
    final seeded = _byEvent[event.remoteId];
    if (seeded == null) return null;

    return SapDetails(
      title: event.title,
      organizationName: event.org,
      schoolYear: event.schoolYear,
      proposalDate: event.on?.subtract(const Duration(days: 35)),
      activityDate: event.on,
      startTime: seeded.start,
      endTime: seeded.end,
      modality: SapModality.faceToFace,
      setting: SapSetting.onCampus,
      venue: seeded.venue,
      personsInCharge: seeded.inCharge,
      expectedStudents: seeded.students,
      totalBudget: event.budget,
      rationale: seeded.rationale,
      objectives: seeded.objectives,
    );
  }

  static List<SapBudgetItem> budgetFor(EventItem event) =>
      _byEvent[event.remoteId]?.budget ?? const [];

  static List<SapSupportRequest> supportFor(EventItem event) =>
      _byEvent[event.remoteId]?.support ?? const [];

  static const _byEvent = <String, _Seeded>{
    'demo-ev-1': _Seeded(
      start: SapTime(8, 0),
      end: SapTime(17, 0),
      venue: 'St. Augustine Building, AVR',
      inCharge: 'Engr. Aileen M. Habaradas, Engr. Glazen M. Perez',
      students: 145,
      rationale:
          'Students have asked for practical security training that the '
          'curriculum does not cover. A one-day workshop with a working '
          'practitioner reaches more of them than a semester elective.',
      objectives:
          'Recognise common attacks on a live system.\n'
          'Use the standard tooling without supervision.\n'
          'Write up findings the way an employer expects.',
      budget: [
        SapBudgetItem(particulars: 'Guest speaker honorarium', amount: '2000.00'),
        SapBudgetItem(particulars: 'Certificates and tokens', amount: '300.00'),
        SapBudgetItem(particulars: 'Seminar materials', amount: '200.00'),
      ],
      support: [
        SapSupportRequest(
          type: SapSupportType.room,
          quantity: 1,
          specify: 'St. Augustine Bldg. AVR, whole day',
        ),
        SapSupportRequest(
          type: SapSupportType.projector,
          quantity: 1,
          specify: 'With HDMI',
        ),
        SapSupportRequest(
          type: SapSupportType.chairs,
          quantity: 150,
          specify: 'Additional 150 chairs',
        ),
      ],
    ),
    'demo-ev-2': _Seeded(
      start: SapTime(13, 0),
      end: SapTime(16, 0),
      venue: 'University Quadrangle',
      inCharge: 'CITE Student Council',
      students: 400,
      rationale:
          'The opening ceremony is what gathers the department before a '
          'week of events, and it is where the organisations introduce '
          'themselves to first years.',
      objectives: 'Open CITE Week.\nIntroduce each organisation.',
      budget: [
        SapBudgetItem(particulars: 'Sound system rental', amount: '8000.00'),
        SapBudgetItem(particulars: 'Snacks', amount: '4000.00'),
      ],
      support: [
        SapSupportRequest(
          type: SapSupportType.sound,
          quantity: 1,
          specify: 'Outdoor, with two microphones',
        ),
        SapSupportRequest(
          type: SapSupportType.tables,
          quantity: 8,
          specify: 'One per organisation',
        ),
      ],
    ),
  };
}

class _Seeded {
  const _Seeded({
    required this.start,
    required this.end,
    required this.venue,
    required this.inCharge,
    required this.students,
    required this.rationale,
    required this.objectives,
    required this.budget,
    required this.support,
  });

  final SapTime start;
  final SapTime end;
  final String venue;
  final String inCharge;
  final int students;
  final String rationale;
  final String objectives;
  final List<SapBudgetItem> budget;
  final List<SapSupportRequest> support;
}
