import '../api/models/academic.dart';
import '../api/models/income.dart';
import '../api/models/inventory.dart';
import '../api/models/receipt.dart';
import '../api/models/remote_expense.dart';
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
    // Last again. With the Dean, and proposed by the officer: the demo's
    // admin is not its proposer, or nobody-decides-their-own would hide the
    // decision from the one role it is here for.
    EventItem(
      remoteId: 'demo-ev-7',
      title: 'CITE Research Colloquium',
      org: 'CITE',
      date: '10 Dec 2026',
      on: DateTime(2026, 12, 10),
      budget: '6000',
      status: EventApprovalStatus.pendingAdmin,
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.departmental,
      proposedBy: 'demo-account-officer',
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
      bool isDraft = false,
    }) => RemoteInventoryItem(
      id: id,
      itemName: name,
      description: description,
      quantity: quantity,
      unit: unit,
      lowStockThreshold: lowStock,
      location: location,
      isDraft: isDraft,
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
      // Bought rather than entered: a purchase writes the row as a draft
      // and an administrator confirms it. The badge, the "Unconfirmed
      // drafts" filter and the notice on the item were all built for
      // this and none of them could appear, because every seeded item
      // was already confirmed — the one question the moderator asked
      // about inventory was the one the demo could not answer.
      item(
        id: 'demo-inv-5',
        name: 'Tarpaulin stand',
        description: 'Adjustable, from the Hack the Future purchase.',
        quantity: 2,
        unit: 'pcs',
        lowStock: 1,
        location: 'CITE stockroom',
        eventId: 'demo-ev-1',
        isDraft: true,
      ),
    ];
  }

  /// The ledger behind each item's stock.
  ///
  /// Every change to stock is a movement, so the figures have to agree:
  /// each list below sums to exactly the quantity the catalog shows. A
  /// ledger that disagreed with the card above it would be worse than
  /// the error message this replaced, and a test holds them in step.
  static List<InventoryMovement> movementsFor(String inventoryId) {
    final now = DateTime.now();
    var serial = 0;
    InventoryMovement move({
      required int change,
      required InventoryMovementType type,
      required String reason,
      required String by,
      required int daysAgo,
      String? eventId,
      String? expenseItemId,
    }) => InventoryMovement(
      id: 'demo-mv-$inventoryId-${serial++}',
      inventoryId: inventoryId,
      eventId: eventId,
      changeQty: change,
      type: type,
      reason: reason,
      performedBy: by,
      expenseItemId: expenseItemId,
      createdAt: now.subtract(Duration(days: daysAgo)),
    );

    return switch (inventoryId) {
      // 15 in, 3 out = 12.
      'demo-inv-1' => [
        move(change: 15, type: InventoryMovementType.openingBalance,
            reason: 'Counted at the start of the school year',
            by: 'Demo Admin', daysAgo: 30),
        move(change: -3, type: InventoryMovementType.issue,
            reason: 'Registration desks, CITE Week',
            by: 'Demo Treasurer', daysAgo: 6, eventId: 'demo-ev-2'),
      ],
      // 4 in, 1 written off = 3, which is why it reads low stock.
      'demo-inv-2' => [
        move(change: 4, type: InventoryMovementType.acquisition,
            reason: 'Bought with last year\'s remaining budget',
            by: 'Demo Admin', daysAgo: 28),
        move(change: -1, type: InventoryMovementType.disposal,
            reason: 'Receiver failed, beyond repair',
            by: 'Demo Admin', daysAgo: 9),
      ],
      // 6 in, 6 out = none left.
      'demo-inv-3' => [
        move(change: 6, type: InventoryMovementType.openingBalance,
            reason: 'Counted at the start of the school year',
            by: 'Demo Admin', daysAgo: 30),
        move(change: -6, type: InventoryMovementType.issue,
            reason: 'Lent to the College of Education, not yet returned',
            by: 'Demo Treasurer', daysAgo: 4),
      ],
      // 500 in, 260 out = 240.
      'demo-inv-4' => [
        move(change: 500, type: InventoryMovementType.purchase,
            reason: 'Ream for the semester',
            by: 'Demo Treasurer', daysAgo: 21),
        move(change: -260, type: InventoryMovementType.issue,
            reason: 'Certificates for CITE Week',
            by: 'Demo Treasurer', daysAgo: 5, eventId: 'demo-ev-2'),
      ],
      // The drafted one: a single movement, the purchase that made it,
      // linked back to the expense line that paid for it.
      'demo-inv-5' => [
        move(change: 2, type: InventoryMovementType.purchase,
            reason: 'From completing the Hack the Future purchase',
            by: 'Demo Treasurer', daysAgo: 2, eventId: 'demo-ev-1',
            expenseItemId: 'demo-exi-1'),
      ],
      _ => const [],
    };
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

  /// Money in. One row is deliberately withheld: an income whose receipt
  /// has not been reviewed is kept out of the totals but still listed,
  /// and a demo that never shows that hides the rule.
  static List<Income> incomes() {
    final now = DateTime.now();
    Income row({
      required String id,
      required String source,
      required FundSource type,
      required String purpose,
      required double amount,
      required int daysAgo,
      ReceiptReviewStatus status = ReceiptReviewStatus.cleared,
    }) => Income(
      id: id,
      eventId: 'demo-ev-1',
      source: source,
      sourceType: type,
      purpose: purpose,
      amount: amount,
      receivedOn: now.subtract(Duration(days: daysAgo)),
      receiptReviewStatus: status,
      recordedBy: 'Demo Treasurer',
      createdAt: now.subtract(Duration(days: daysAgo)),
    );

    return [
      row(
        id: 'demo-in-1',
        source: 'Participant registration',
        type: FundSource.registrationFees,
        purpose: 'Seminar kits and certificates',
        amount: 7250,
        daysAgo: 12,
      ),
      row(
        id: 'demo-in-2',
        source: 'Bulacan Tech Solutions',
        type: FundSource.sponsorship,
        purpose: "Speaker's honorarium",
        amount: 5000,
        daysAgo: 9,
      ),
      row(
        id: 'demo-in-3',
        source: 'CITE Alumni Chapter',
        type: FundSource.donation,
        purpose: 'Tarpaulin and printing',
        amount: 1500,
        daysAgo: 4,
        status: ReceiptReviewStatus.pending,
      ),
    ];
  }

  /// The itemized lines behind a demo expense.
  ///
  /// `demo-ex-2` carries asset lines on purpose: asset lines are what
  /// make Complete purchase reachable, which is the only path in the app
  /// from spending money to owning equipment.
  static List<ExpenseLine> linesFor(String expenseId) {
    final now = DateTime.now();
    var serial = 0;
    ExpenseLine line({
      required String name,
      required double amount,
      required ItemCategory category,
      int quantity = 1,
      String unit = 'pcs',
    }) => ExpenseLine(
      id: 'demo-exl-$expenseId-${serial++}',
      expenseId: expenseId,
      name: name,
      amount: amount,
      category: category,
      quantity: quantity,
      unit: unit,
      convertedInventoryId: null,
      createdAt: now.subtract(const Duration(days: 8)),
    );

    return switch (expenseId) {
      // 1,850 total: two assets worth keeping, one consumable.
      'demo-ex-2' => [
        line(
          name: 'Extension cord 10m',
          amount: 850,
          category: ItemCategory.asset,
          quantity: 2,
        ),
        line(
          name: 'Whiteboard marker set',
          amount: 600,
          category: ItemCategory.asset,
          quantity: 6,
          unit: 'sets',
        ),
        line(
          name: 'Bond paper, short',
          amount: 400,
          category: ItemCategory.consumable,
          quantity: 5,
          unit: 'reams',
        ),
      ],
      'demo-ex-1' => [
        line(
          name: "Speaker's honorarium",
          amount: 2000,
          category: ItemCategory.consumable,
        ),
      ],
      'demo-ex-3' => [
        line(
          name: 'Certificate printing',
          amount: 2850,
          category: ItemCategory.consumable,
          quantity: 145,
        ),
      ],
      _ => const [],
    };
  }

  /// The figures the Analytics sheet and the dashboard's analytics
  /// section read. Derived from the same seed the other screens use, so
  /// the counts agree with what is on the lists rather than being a
  /// second set of numbers that happens to look plausible.
  static DashboardSummary dashboard() => DashboardSummary(
    totalCategories: categories().length,
    totalAllocatedBudget: 50000,
    totalRemainingBudget: 35550,
    eventsByStatus: {
      'pending_adviser': 1,
      'approved': 1,
      'rejected': 1,
      'draft': 2,
      'completed': 1,
    },
    expensesByStatus: {'pending': 1, 'approved': 2, 'rejected': 1},
    flaggedExpenseCount: 1,
    lowStockItemCount: 2,
    draftInventoryCount: 1,
  );

  /// Six months of spending, ending on the current month so the chart
  /// never reads as stale during a walkthrough.
  static List<SpendingTrendPoint> spendingTrends() {
    final now = DateTime.now();
    const amounts = [3200.0, 5400.0, 2100.0, 8750.0, 6300.0, 14450.0];
    const counts = [2, 3, 1, 5, 4, 4];
    return [
      for (var back = 5; back >= 0; back--)
        () {
          final month = DateTime(now.year, now.month - back);
          final index = 5 - back;
          return SpendingTrendPoint(
            month: '${month.year}-${month.month.toString().padLeft(2, '0')}',
            totalAmount: amounts[index],
            expenseCount: counts[index],
          );
        }(),
    ];
  }

  /// The receipt history behind the expenses, newest first.
  ///
  /// One pair is deliberately alike — same merchant, same amount, a day
  /// apart — because the similarity flag is the point of this screen and
  /// a history with nothing flagged in it never shows what it is for.
  static List<Receipt> receipts() {
    final now = DateTime.now();
    Receipt row({
      required String id,
      required String purpose,
      required String merchant,
      required double amount,
      required int daysAgo,
      String? expenseId,
      bool flagged = false,
      List<String> similar = const [],
      ReceiptReviewStatus status = ReceiptReviewStatus.cleared,
    }) => Receipt(
      id: id,
      organizationId: 'demo-org-1',
      departmentId: 'demo-dept-1',
      eventId: 'demo-ev-1',
      expenseId: expenseId,
      incomeId: null,
      purpose: purpose,
      receiptUrl: 'demo://receipts/$id.jpg',
      merchant: merchant,
      // Never captured by the app yet, which is why the exact duplicate
      // check can only run on two of its three keys.
      receiptNumber: null,
      issuedOn: now.subtract(Duration(days: daysAgo)),
      amount: amount,
      isFlagged: flagged,
      similarReceiptIds: similar,
      reviewStatus: status,
      reviewReason: flagged
          ? 'Same merchant and amount within a day of demo-rc-3.'
          : null,
      reviewedBy: status == ReceiptReviewStatus.cleared ? 'Demo Adviser' : null,
      reviewedAt: status == ReceiptReviewStatus.cleared
          ? now.subtract(Duration(days: daysAgo - 1))
          : null,
      recordedBy: 'Demo Treasurer',
      createdAt: now.subtract(Duration(days: daysAgo)),
    );

    return [
      row(
        id: 'demo-rc-4',
        purpose: 'Tarpaulin and printing',
        merchant: 'PrintHub',
        amount: 4600,
        daysAgo: 2,
        expenseId: 'demo-ex-4',
        flagged: true,
        similar: const ['demo-rc-3'],
        status: ReceiptReviewStatus.pending,
      ),
      row(
        id: 'demo-rc-3',
        purpose: 'Tarpaulin and printing',
        merchant: 'PrintHub',
        amount: 4600,
        daysAgo: 3,
      ),
      row(
        id: 'demo-rc-2',
        purpose: 'Seminar materials',
        merchant: 'National Book Store',
        amount: 1850,
        daysAgo: 8,
        expenseId: 'demo-ex-2',
      ),
      row(
        id: 'demo-rc-1',
        purpose: "Speaker's honorarium",
        merchant: 'Hack the Future',
        amount: 2000,
        daysAgo: 14,
        expenseId: 'demo-ex-1',
      ),
    ];
  }

  /// What the OCR would have read off a photographed receipt. The figures
  /// add up to the total, because a scan whose lines do not reconcile is
  /// exactly what the real parser refuses.
  static ScannedReceipt scannedReceipt() => ScannedReceipt(
    receiptUrl: 'demo://receipts/lcup-campus-store.jpg',
    merchant: 'LCUP Campus Store',
    date: DateTime.now().subtract(const Duration(days: 1)),
    amount: 1220,
    items: [
      ScannedReceiptLine(
        name: 'Tarpaulin 3x5',
        amount: 450,
        category: ItemCategory.consumable,
      ),
      ScannedReceiptLine(
        name: 'Certificates (bond)',
        amount: 600,
        category: ItemCategory.consumable,
      ),
      ScannedReceiptLine(
        name: 'Ribbon spool',
        amount: 170,
        category: ItemCategory.asset,
      ),
    ],
  );

  static List<AppNotice> notices() => [
    // True of demo-ev-1, which is sent and with the Moderator.
    AppNotice(
      id: 'demo-n-1',
      kind: 'sap_submitted',
      emailStatus: 'sent',
      title: 'SAP proposal submitted',
      body:
          'Sent for department review. HACK THE FUTURE is with your '
          'Moderator.',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      readAt: null,
      // Named, so tapping it opens the event the way a real workflow
      // notice does. Without this the demo cannot show that at all.
      payload: const {'event_id': 'demo-ev-1', 'action': 'sap_submitted'},
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

  /// Part 4, for the events the SDS Office has been through or has now.
  /// Null for the rest: a proposal still with the Moderator or the Dean has
  /// not reached the office, and the review screen waits on it to sign.
  static SapClearance? clearanceFor(EventItem event) =>
      _clearances[event.remoteId];

  static const _clearances = <String, SapClearance>{
    'demo-ev-2': SapClearance(
      parentsConsent: SapClearanceAnswer.notApplicable,
      parentsConsentReason: 'On campus, within school hours.',
      attachments: 'Program of activities, budget and endorsement letter',
      classInterruption: SapClearanceAnswer.none,
      medicalExam: SapClearanceAnswer.notApplicable,
      medicalExamReason: 'No strenuous activity.',
      reportOfCompliance: SapClearanceAnswer.yes,
      studentPersonnelRatio: '400:8',
    ),
    'demo-ev-5': SapClearance(
      parentsConsent: SapClearanceAnswer.notApplicable,
      parentsConsentReason: 'On campus, within school hours.',
      attachments: 'Program of activities and budget',
      classInterruption: SapClearanceAnswer.none,
      medicalExam: SapClearanceAnswer.notApplicable,
      medicalExamReason: 'No strenuous activity.',
      reportOfCompliance: SapClearanceAnswer.yes,
      studentPersonnelRatio: '300:6',
    ),
    // With the office to sign, so the pad opens on it.
    'demo-ev-6': SapClearance(
      parentsConsent: SapClearanceAnswer.notApplicable,
      parentsConsentReason: 'On campus, within school hours.',
      attachments: 'Program of activities, budget and speaker profile',
      classInterruption: SapClearanceAnswer.none,
      medicalExam: SapClearanceAnswer.notApplicable,
      medicalExamReason: 'No strenuous activity.',
      reportOfCompliance: SapClearanceAnswer.yes,
      studentPersonnelRatio: '80:2',
    ),
  };

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
    // With the Dean, so the demo's admin has a whole proposal to read and
    // decide. The three items add up to what the event asks for.
    'demo-ev-7': _Seeded(
      start: SapTime(9, 0),
      end: SapTime(16, 0),
      venue: 'St. Augustine Building, AVR',
      inCharge: 'Engr. Aileen M. Habaradas',
      students: 100,
      rationale:
          'Capstone teams face a panel without having seen how research in '
          'the department is framed and reported. A day of short talks from '
          'faculty and graduate students gives them something to write to '
          'before the proposal defenses.',
      objectives:
          'Hear how faculty research is framed and reported.\n'
          'Ask what a defensible methodology looks like.\n'
          'Take away a template for a research abstract.',
      budget: [
        SapBudgetItem(
          particulars: 'Invited speaker honorarium',
          amount: '3000.00',
        ),
        SapBudgetItem(
          particulars: 'Snacks',
          quantity: 100,
          unitCost: '20.00',
          amount: '2000.00',
        ),
        SapBudgetItem(
          particulars: 'Programs and certificates',
          quantity: 100,
          unitCost: '10.00',
          amount: '1000.00',
        ),
      ],
      support: [
        SapSupportRequest(
          type: SapSupportType.room,
          quantity: 1,
          specify: 'St. Augustine Bldg. AVR, 9:00 AM to 4:00 PM',
        ),
        SapSupportRequest(
          type: SapSupportType.sound,
          quantity: 1,
          specify: 'Two microphones',
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
