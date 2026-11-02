import '../api/models/academic.dart';
import '../api/models/income.dart';
import '../api/models/inventory.dart';
import '../api/models/reports.dart';
import '../api/models/proposal_letter.dart';
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
    // One id per role, not one for the demo.
    //
    // Every role shared 'demo-account' and every seeded event is
    // proposed by the treasurer, so the self-review guard — nobody
    // decides on their own proposal — fired for the adviser too. No
    // role could review anything, which is the whole two-stage flow.
    id: 'demo-account-${role.name}',
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
      proposedBy: 'demo-account-treasurer',
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
      proposedBy: 'demo-account-treasurer',
    ),
    EventItem(
      remoteId: 'demo-ev-3',
      title: 'Industry Immersion Talk',
      org: 'ACPES',
      date: '5 Nov 2026',
      on: DateTime(2026, 11, 5),
      budget: '8000',
      status: EventApprovalStatus.rejected,
      // The SDS Office's alone to give: the Moderator and the Dean return a
      // proposal, they do not reject it.
      rejectedBy: 'the SDS Office',
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.organizational,
      proposedBy: 'demo-account-treasurer',
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
      proposedBy: 'demo-account-treasurer',
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
      proposedBy: 'demo-account-treasurer',
    ),
    // Last, so the numbering above holds. Past the Moderator and the Dean
    // and with the SDS Office: the one the demo's SDS role has to review
    // and sign, which nothing else here is.
    EventItem(
      remoteId: 'demo-ev-6',
      title: 'Cloud Computing Workshop for Capstone Teams',
      org: 'ACPES',
      date: '19 Nov 2026',
      on: DateTime(2026, 11, 19),
      budget: '4500',
      status: EventApprovalStatus.pendingInstitutional,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.organizational,
      proposedBy: 'demo-account-treasurer',
    ),
  ];

  /// A consolidated financial report, so the Reports screen has one.
  ///
  /// Without it `financialReport` is null, and the download window hides
  /// its whole "This report" half — the totals card and the PDF / CSV /
  /// print-ready row the moderator asked for. Only the dashboard
  /// snapshot showed, which offers two formats, so the feature looked
  /// half-built in the one place it gets filmed.
  static ConsolidatedFinancialReport financialReport() {
    FinancialEventSummary event({
      required String id,
      required String title,
      required double income,
      required double expenses,
    }) => FinancialEventSummary(
      eventId: id,
      title: title,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.organizational,
      incomeCount: income > 0 ? 2 : 0,
      expenseCount: expenses > 0 ? 3 : 0,
      totalIncome: income,
      totalExpenses: expenses,
      netBalance: income - expenses,
      withheldIncomeTotal: 0,
      withheldIncomeCount: 0,
    );

    final events = [
      event(
        id: 'demo-ev-1',
        title: 'HACK THE FUTURE: Cybersecurity and Ethical Hacking',
        income: 7250,
        expenses: 2500,
      ),
      event(
        id: 'demo-ev-2',
        title: 'CITE Week: Opening Ceremony',
        income: 12000,
        expenses: 11950,
      ),
      event(
        id: 'demo-ev-5',
        title: 'Capstone Project Exhibit',
        income: 0,
        expenses: 0,
      ),
    ];

    final income = events.fold<double>(0, (sum, e) => sum + e.totalIncome);
    final spent = events.fold<double>(0, (sum, e) => sum + e.totalExpenses);

    return ConsolidatedFinancialReport(
      period: ReportPeriod.semester,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 12, 20),
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: null,
      totalIncome: income,
      totalExpenses: spent,
      unassignedExpenseTotal: 0,
      netBalance: income - spent,
      events: events,
      incomeBySource: [
        IncomeSourceSummary(
          sourceType: FundSource.registrationFees,
          source: 'Registration fees',
          incomeCount: 2,
          totalIncome: 14500,
        ),
        IncomeSourceSummary(
          sourceType: FundSource.sponsorship,
          source: 'Sponsorship',
          incomeCount: 1,
          totalIncome: 3500,
        ),
        IncomeSourceSummary(
          sourceType: FundSource.donation,
          source: 'Donation',
          incomeCount: 1,
          totalIncome: 1250,
        ),
      ],
      withheldIncomeTotal: 0,
      withheldIncomeCount: 0,
    );
  }

  /// One event's finances, for the demo. The real one comes from
  /// `/reports/event/{id}`, which the demo cannot call.
  static EventReport? eventReportFor(EventItem event) {
    final id = event.remoteId;
    if (id == null) return null;

    final figures = <String, (double allocated, double income, double spent)>{
      'demo-ev-2': (12000, 12000, 11950),
      'demo-ev-5': (6000, 1250, 5400),
    };
    final found = figures[id];
    if (found == null) return null;

    final (allocated, income, spent) = found;
    return EventReport(
      eventId: id,
      title: event.title,
      status: event.statusLabel,
      schoolYear: event.schoolYear,
      semester: Semester.first,
      eventScope: EventScope.departmental,
      estimatedCost: allocated,
      allocatedBudget: allocated,
      remainingBudget: allocated - spent,
      totalIncome: income,
      totalSpent: spent,
      netBalance: income - spent,
      incomeBySource: [
        IncomeSourceSummary(
          sourceType: FundSource.registrationFees,
          source: 'Registration fees',
          incomeCount: 1,
          totalIncome: income * 0.8,
        ),
        IncomeSourceSummary(
          sourceType: FundSource.sponsorship,
          source: 'Sponsorship',
          incomeCount: 1,
          totalIncome: income * 0.2,
        ),
      ],
      // One event carries a withheld entry, so the line that says
      // withheld income is not income has something to describe.
      withheldIncomeTotal: id == 'demo-ev-5' ? 750 : 0,
      withheldIncomeCount: id == 'demo-ev-5' ? 1 : 0,
    );
  }

  /// Letters submitted for events.
  ///
  /// Reading these is the SDS Staff role's only permission, so an empty
  /// list made that whole role look broken: signing in as the office
  /// landed on "No letters yet" and there was nothing else it could
  /// reach.
  ///
  /// The stored value is a storage path rather than an https link. The
  /// screen shows it as text to copy and never fetches it, and a URL to
  /// a host that does not exist would read as a working link.
  static List<ProposalLetter> letters() {
    final now = DateTime.now();
    return [
      ProposalLetter(
        id: 'demo-let-1',
        eventId: 'demo-ev-1',
        title: 'Request for approval — HACK THE FUTURE',
        documentUrl: 'proposal-letters/demo-ev-1/request-for-approval.pdf',
        submittedBy: 'demo-user-treasurer',
        createdAt: now.subtract(const Duration(days: 6)),
      ),
      ProposalLetter(
        id: 'demo-let-2',
        eventId: 'demo-ev-2',
        title: 'Letter of intent — CITE Week',
        documentUrl: 'proposal-letters/demo-ev-2/letter-of-intent.pdf',
        submittedBy: 'demo-user-officer',
        createdAt: now.subtract(const Duration(days: 20)),
      ),
      // A photographed letter, so the list shows both document kinds and
      // the icon that goes with each.
      ProposalLetter(
        id: 'demo-let-3',
        eventId: 'demo-ev-3',
        title: 'Endorsement — Industry Immersion Talk',
        documentUrl: 'proposal-letters/demo-ev-3/endorsement-signed.jpg',
        submittedBy: 'demo-user-adviser',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  /// Equipment the organization holds, so the Inventory screen is not
  /// empty in a demo — and so the low-stock and none-left filters have
  /// something to find. Two are linked to events, which is the link the
  /// moderator asked about; one deliberately is not.
  static List<RemoteInventoryItem> catalog() {
    final now = DateTime.now();
    RemoteInventoryItem item({
      required String id,
      required String name,
      required String description,
      required int quantity,
      required String unit,
      required int lowStock,
      required String location,
      String? eventId,
    }) => RemoteInventoryItem(
      id: id,
      itemName: name,
      description: description,
      quantity: quantity,
      unit: unit,
      lowStockThreshold: lowStock,
      location: location,
      isDraft: false,
      eventId: eventId,
      departmentId: 'demo-dept-1',
      organizationId: 'demo-org-1',
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );

    return [
      item(
        id: 'demo-inv-1',
        name: 'Folding tables',
        description: 'Six-foot trestle tables for registration desks.',
        quantity: 12,
        unit: 'pcs',
        lowStock: 4,
        location: 'CITE stockroom',
        eventId: 'demo-ev-2',
      ),
      item(
        id: 'demo-inv-2',
        name: 'Wireless microphone',
        description: 'Handheld, with receiver and spare batteries.',
        quantity: 3,
        unit: 'sets',
        lowStock: 4,
        location: 'AV cabinet',
        eventId: 'demo-ev-1',
      ),
      item(
        id: 'demo-inv-3',
        name: 'Extension cords',
        description: 'Ten metres, three-gang.',
        quantity: 0,
        unit: 'pcs',
        lowStock: 2,
        location: 'AV cabinet',
      ),
      item(
        id: 'demo-inv-4',
        name: 'Certificate paper',
        description: 'A4 parchment, for the nine printed signatures.',
        quantity: 240,
        unit: 'sheets',
        lowStock: 50,
        location: 'CITE stockroom',
      ),
    ];
  }

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
      // Named, so tapping it opens the event the way a real workflow
      // notice does. Without this the demo cannot show that at all.
      payload: const {'event_id': 'demo-ev-1', 'action': 'sap_cleared'},
    ),
    // As the server words a rejection. The reasons are on the proposal, not
    // in the notice.
    AppNotice(
      id: 'demo-n-2',
      kind: 'sap_rejected',
      emailStatus: 'sent',
      title: 'SAP proposal rejected',
      body: 'The SDS Office rejected Industry Immersion Talk.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      readAt: null,
      payload: const {'event_id': 'demo-ev-3', 'action': 'sap_rejected'},
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
  /// Why the SDS Office rejected a proposal, for the one seeded event it
  /// turned down. Without it the demo shows a rejected proposal with no
  /// reason attached, which is the thing that was wrong before.
  ///
  /// A rejection is final, so this asks for nothing to be sent back.
  static String? sdsRemarksFor(EventItem event) => event.remoteId == 'demo-ev-3'
      // True of what is actually seeded: a 9:00 start, and Part 3's
      // excuse arrangement left blank. A reason that describes rows the
      // form does not have is worse than no reason.
      ? 'A 9:00 start takes these students out of morning classes, and '
            'Part 3 sets out no excuse letter arrangement for them. The '
            'activity cannot be approved as proposed.'
      : null;

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
        // The paper gives this one a flat fee and no count.
        SapBudgetItem(particulars: 'Guest speaker honorarium', amount: '2000.00'),
        // These two read across the way the paper does, so the demo
        // shows the quantity and unit cost columns rather than only the
        // rows that have neither.
        SapBudgetItem(
          particulars: 'Certificates and tokens',
          quantity: 150,
          unitCost: '2.00',
          amount: '300.00',
        ),
        SapBudgetItem(
          particulars: 'Seminar materials',
          quantity: 40,
          unitCost: '5.00',
          amount: '200.00',
        ),
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
        SapBudgetItem(
          particulars: 'Snacks',
          quantity: 400,
          unitCost: '10.00',
          amount: '4000.00',
        ),
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
    // The one the SDS Office turns down. It is seeded because its reason
    // names Part 3 — a reason pointing at an empty part is worse than no
    // reason, and this is the flow the demonstration walks.
    'demo-ev-3': _Seeded(
      start: SapTime(9, 0),
      end: SapTime(11, 30),
      venue: 'St. Augustine Building, Room 204',
      inCharge: 'Engr. Aileen M. Habaradas',
      students: 60,
      rationale:
          'Third and fourth years asked to hear from people doing the '
          'work. A practitioner session is the cheapest way to give them '
          'that before immersion placements are chosen.',
      objectives:
          'Hear how the industry actually hires.\n'
          'Ask about the placements on offer this year.',
      budget: [
        SapBudgetItem(particulars: 'Speaker honorarium', amount: '3000.00'),
        SapBudgetItem(
          particulars: 'Printed handouts',
          quantity: 60,
          unitCost: '25.00',
          amount: '1500.00',
        ),
      ],
      support: [
        SapSupportRequest(
          type: SapSupportType.projector,
          quantity: 1,
          specify: 'With HDMI',
        ),
      ],
    ),
    // With the SDS Office, so the office has a whole proposal to read and
    // sign. The three items add up to what the event asks for.
    'demo-ev-6': _Seeded(
      start: SapTime(13, 0),
      end: SapTime(17, 0),
      venue: 'St. Augustine Building, Room 301',
      inCharge: 'Engr. Glazen M. Perez',
      students: 80,
      rationale:
          'Capstone teams build on a laptop and meet a real host for the '
          'first time at the panel. A half-day workshop on putting a '
          'project online, before the defenses, gives every team the same '
          'starting point.',
      objectives:
          'Put a small web application online.\n'
          'Read a hosting bill before it arrives.\n'
          'Know what to show the panel about where it runs.',
      budget: [
        SapBudgetItem(
          particulars: 'Resource speaker honorarium',
          amount: '2500.00',
        ),
        SapBudgetItem(
          particulars: 'Snacks',
          quantity: 80,
          unitCost: '15.00',
          amount: '1200.00',
        ),
        SapBudgetItem(
          particulars: 'Certificates and handouts',
          quantity: 80,
          unitCost: '10.00',
          amount: '800.00',
        ),
      ],
      support: [
        SapSupportRequest(
          type: SapSupportType.room,
          quantity: 1,
          specify: 'St. Augustine Bldg. Room 301, 1:00 to 5:00 PM',
        ),
        SapSupportRequest(
          type: SapSupportType.projector,
          quantity: 1,
          specify: 'With HDMI',
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
