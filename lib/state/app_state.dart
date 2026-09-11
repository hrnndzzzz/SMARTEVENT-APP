import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/category_service.dart';
import '../api/models/category.dart';

enum UserRole { officer, adviser, admin }

class InventoryItem {
  final IconData icon;
  final String name;
  final String description;
  int qty;
  final int initialQty;
  final int lowStockThreshold;

  InventoryItem({
    required this.icon,
    required this.name,
    required this.description,
    required this.qty,
    this.lowStockThreshold = 2,
  }) : initialQty = qty;

  bool get isLowStock => qty < lowStockThreshold;
  bool get hasBeenIssued => qty < initialQty;
}

enum EventApprovalStatus { pendingAdviser, pendingAdmin, approved, rejected }

class EventItem {
  String title;
  String org;
  String date;
  String venue;
  String budget;
  String attendees;

  EventApprovalStatus status;
  String? rejectedBy;
  String? adviserApprovalNote;
  String? adminApprovalNote;

  int checkedIn;
  String? adviserComment;
  int? adviserRating;

  String get statusLabel => switch (status) {
    EventApprovalStatus.pendingAdviser => 'Pending Adviser Review',
    EventApprovalStatus.pendingAdmin => 'Pending Admin Approval',
    EventApprovalStatus.approved => 'Approved',
    EventApprovalStatus.rejected => 'Rejected by ${rejectedBy ?? 'Reviewer'}',
  };

  int get expectedAttendees {
    final match = RegExp(r'\d+').firstMatch(attendees);
    return match != null ? int.parse(match.group(0)!) : 0;
  }

  bool get hasFeedback => adviserComment != null || adviserRating != null;

  EventItem({
    required this.title,
    required this.org,
    required this.date,
    required this.venue,
    required this.budget,
    required this.attendees,
    this.status = EventApprovalStatus.pendingAdviser,
    this.rejectedBy,
    this.adviserApprovalNote,
    this.adminApprovalNote,
    this.checkedIn = 0,
    this.adviserComment,
    this.adviserRating,
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
  String name;
  String email;
  final String password;
  UserRole role;
  Department department;

  Account({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.department = Department.systemWide,
  });
}

/// Matches the real backend: an expense starts pending and must be
/// reviewed before it counts toward spending. Unlike events, either
/// an Adviser OR an Admin can resolve it — no two-stage sequence here.
enum ExpenseStatus { pending, approved, rejected }

class ExpenseEntry {
  final String vendor;
  final double amount;
  final String category;
  ExpenseStatus status;
  String? reviewedBy; // 'Adviser' or 'Admin', set once resolved
  String? reviewNote;

  ExpenseEntry({
    required this.vendor,
    required this.amount,
    required this.category,
    this.status = ExpenseStatus.pending,
    this.reviewedBy,
    this.reviewNote,
  });
}

class AppState extends ChangeNotifier {
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

  Future<void> loadCategories() async {
    try {
      categories = await _categoryService.list();
      notifyListeners();
    } catch (_) {
      // Silent failure is acceptable — screens just show ₱0 until the
      // relevant screen is reopened once connectivity is restored.
    }
  }

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
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  final List<ExpenseEntry> expenses = [
    ExpenseEntry(vendor: 'Fresh Campus Catering', amount: 950.00, category: 'Catering'),
    ExpenseEntry(vendor: 'CITE Auditorium Rental', amount: 650.00, category: 'Venue'),
    ExpenseEntry(vendor: 'National Bookstore', amount: 350.00, category: 'Equipment'),
    ExpenseEntry(vendor: 'Print Shop Flyers', amount: 200.00, category: 'Marketing'),
  ];

  List<String> get expenseLog =>
      expenses.map((e) => '${e.vendor} · -₱${e.amount.toStringAsFixed(2)}').toList();

  void logExpense(String vendor, double amount, {String category = 'Equipment'}) {
    expenses.insert(0, ExpenseEntry(vendor: vendor, amount: amount, category: category));
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

  /// Returns null on success, or an error message if approving would
  /// overdraw the category's remaining budget — matching the real
  /// backend's hard block on this.
  String? approveExpense(ExpenseEntry expense, {required String reviewerRole, String? note}) {
    final remaining = (categoryBudgets[expense.category] ?? 0) - (spendByCategory[expense.category] ?? 0);
    if (expense.amount > remaining) {
      addNotification(AppNotification(
        icon: Icons.warning_amber_rounded,
        tagColor: const Color(0xFFC1503D),
        title: 'Blocked: ${expense.vendor}',
        body: '${expense.category} only has ₱${remaining.toStringAsFixed(2)} left — '
            'this expense (₱${expense.amount.toStringAsFixed(2)}) needs a higher budget before it can be approved.',
        time: 'Just now',
        destination: NotifDestination.dashboard,
        targetRoles: {UserRole.admin},
      ));
      notifyListeners();
      return 'Approving this (₱${expense.amount.toStringAsFixed(2)}) would exceed '
          '${expense.category}\'s remaining budget (₱${remaining.toStringAsFixed(2)}). '
          'Ask an Admin to increase the budget, or reject this expense instead.';
    }
    expense.status = ExpenseStatus.approved;
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
  }

  void rejectExpense(ExpenseEntry expense, {required String reviewerRole, String? note}) {
    expense.status = ExpenseStatus.rejected;
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
  }

  final List<InventoryItem> inventory = [
    InventoryItem(
      icon: Icons.cable,
      name: 'HDMI Cables (4K 10m)',
      description: 'High-speed AV connectivity.',
      qty: 1,
    ),
    InventoryItem(
      icon: Icons.campaign_outlined,
      name: 'PA Sound System Set',
      description: 'Includes 2 speakers, mixer, and wireless mics.',
      qty: 4,
    ),
  ];

  final List<String> inventoryLog = [
    'PA System — checked out by J. Doe · 2h ago',
    'Projector Screen — returned by S. Smith · 5h ago',
  ];

  int get lowStockCount => inventory.where((i) => i.isLowStock).length;

  void issueItem(InventoryItem item) {
    if (item.qty <= 0) return;
    item.qty -= 1;
    inventoryLog.insert(0, '${item.name} — issued · just now');
    if (item.isLowStock) {
      addNotification(AppNotification(
        icon: Icons.warning_amber_rounded,
        tagColor: const Color(0xFFC1503D),
        title: 'Low stock: ${item.name}',
        body: 'Only ${item.qty} unit${item.qty == 1 ? '' : 's'} remaining, below minimum threshold.',
        time: 'Just now',
        destination: NotifDestination.inventory,
        targetRoles: {UserRole.officer},
      ));
    }
    notifyListeners();
  }

  void restockItem(InventoryItem item, {int amount = 5}) {
    item.qty += amount;
    inventoryLog.insert(0, '${item.name} — restocked +$amount · just now');
    notifyListeners();
  }

  final List<EventItem> events = [
    EventItem(
      title: 'Annual Fall Hackathon',
      org: 'Engineering Soc.',
      date: 'Oct 12-14, 2026',
      venue: 'CITE Auditorium',
      budget: '₱8,200.00',
      attendees: '62',
      status: EventApprovalStatus.approved,
    ),
    EventItem(
      title: 'Leadership Summit 2026',
      org: 'CITE Student Council',
      date: 'Nov 20, 2026',
      venue: 'CITE Auditorium',
      budget: '₱8,200.00',
      attendees: '120 (expected)',
      status: EventApprovalStatus.pendingAdviser,
    ),
  ];

  void addEvent(EventItem event, {required UserRole creatorRole}) {
    switch (creatorRole) {
      case UserRole.officer:
        event.status = EventApprovalStatus.pendingAdviser;
        break;
      case UserRole.adviser:
        event.status = EventApprovalStatus.pendingAdmin;
        break;
      case UserRole.admin:
        event.status = EventApprovalStatus.approved;
        break;
    }

    events.insert(0, event);

    switch (event.status) {
      case EventApprovalStatus.pendingAdviser:
        addNotification(AppNotification(
          icon: Icons.event_outlined,
          tagColor: const Color(0xFFE8A33D),
          title: 'New proposal to review',
          body: '${event.title} is awaiting your review.',
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
          body: '${event.title} is awaiting your final approval.',
          time: 'Just now',
          destination: NotifDestination.events,
          targetRoles: {UserRole.admin},
        ));
        break;
      case EventApprovalStatus.approved:
        addNotification(AppNotification(
          icon: Icons.check_circle_outline,
          tagColor: const Color(0xFF3F8272),
          title: 'Event auto-approved',
          body: '${event.title} was created by Admin and is now active.',
          time: 'Just now',
          destination: NotifDestination.events,
          targetRoles: {UserRole.officer, UserRole.adviser},
        ));
        break;
      case EventApprovalStatus.rejected:
        break;
    }

    notifyListeners();
  }

  void updateEvent() {
    notifyListeners();
  }

  void resubmitEvent(EventItem event) {
    event.status = EventApprovalStatus.pendingAdviser;
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

  void adviserDecision(EventItem event, {required bool approved, String? note}) {
    event.adviserApprovalNote = note;
    if (approved) {
      event.status = EventApprovalStatus.pendingAdmin;
      addNotification(AppNotification(
        icon: Icons.fact_check_outlined,
        tagColor: const Color(0xFFE8A33D),
        title: 'Advanced to Admin: ${event.title}',
        body: 'Approved by adviser, now awaiting final admin approval.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.admin, UserRole.officer},
      ));
    } else {
      event.status = EventApprovalStatus.rejected;
      event.rejectedBy = 'Adviser';
      addNotification(AppNotification(
        icon: Icons.cancel_outlined,
        tagColor: const Color(0xFFC1503D),
        title: 'Rejected by Adviser: ${event.title}',
        body: note?.isNotEmpty == true ? note! : 'No reason given.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.officer},
      ));
    }
    notifyListeners();
  }

  void adminDecision(EventItem event, {required bool approved, String? note}) {
    event.adminApprovalNote = note;
    if (approved) {
      event.status = EventApprovalStatus.approved;
      addNotification(AppNotification(
        icon: Icons.check_circle_outline,
        tagColor: const Color(0xFF3F8272),
        title: 'Approved: ${event.title}',
        body: 'Final approval granted. Event is now active.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.officer, UserRole.adviser},
      ));
    } else {
      event.status = EventApprovalStatus.rejected;
      event.rejectedBy = 'Admin';
      addNotification(AppNotification(
        icon: Icons.cancel_outlined,
        tagColor: const Color(0xFFC1503D),
        title: 'Rejected by Admin: ${event.title}',
        body: note?.isNotEmpty == true ? note! : 'No reason given.',
        time: 'Just now',
        destination: NotifDestination.events,
        targetRoles: {UserRole.officer, UserRole.adviser},
      ));
    }
    notifyListeners();
  }

  void checkInAttendee(EventItem event) {
    event.checkedIn += 1;
    notifyListeners();
  }

  void resetAttendance(EventItem event) {
    event.checkedIn = 0;
    notifyListeners();
  }

  void submitFeedback(EventItem event, {required int rating, required String comment}) {
    event.adviserRating = rating;
    event.adviserComment = comment;
    addNotification(AppNotification(
      icon: Icons.rate_review_outlined,
      tagColor: const Color(0xFF3F8272),
      title: 'Feedback submitted: ${event.title}',
      body: 'Rated $rating/5 by adviser.',
      time: 'Just now',
      destination: NotifDestination.events,
      targetRoles: {UserRole.officer},
    ));
    notifyListeners();
  }

  final List<AppNotification> notifications = [
    AppNotification(
      icon: Icons.warning_amber_rounded,
      tagColor: const Color(0xFFC1503D),
      title: 'Low stock: HDMI Cables (4K 10m)',
      body: 'Only 1 unit remaining, below minimum threshold.',
      time: '10 min ago',
      destination: NotifDestination.inventory,
      targetRoles: {UserRole.officer},
    ),
    AppNotification(
      icon: Icons.fact_check_outlined,
      tagColor: const Color(0xFFE8A33D),
      title: 'Pending approval: Leadership Summit 2026',
      body: 'Awaiting your review.',
      time: '2 hrs ago',
      targetRoles: {UserRole.adviser},
    ),
  ];

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

  final List<Account> _accounts = [
    // Mirrors the real backend's bootstrap step (a manually-inserted
    // first admin, since registration itself is admin-only with no
    // self-service path at all) — one seeded Admin account so there's
    // always a way in on a fresh install.
    Account(
      name: 'System Administrator',
      email: 'admin@lcup.edu.ph',
      password: 'admin123',
      role: UserRole.admin,
    ),
  ];

  Account? currentAccount;
  UserRole? currentRole;

  final ApiClient _apiClient = ApiClient();
  late final AuthService _authService = AuthService(_apiClient);

  UserRole _roleFromString(String role) => switch (role) {
    'adviser' => UserRole.adviser,
    'admin' => UserRole.admin,
    _ => UserRole.officer,
  };

  /// Admin-only, now a REAL backend call. Requires the caller to
  /// already be signed in as Admin (enforced server-side too, not
  /// just by hiding the UI).
  Future<String?> registerUser({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    Department department = Department.cite,
  }) async {
    try {
      await _authService.registerUser(
        fullName: name,
        email: email,
        password: password,
        role: role.name,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  /// REAL backend call: logs in, then fetches the signed-in user's
  /// profile (login alone doesn't return it). On success, bridges the
  /// result into the existing local Account/UserRole model so the rest
  /// of the app keeps working unchanged.
  ///
  /// TEMP DEBUG: the catch below shows the raw exception in the
  /// snackbar instead of a generic message, so we can see exactly
  /// what's actually failing. Revert to the generic message once
  /// diagnosed.
  /// REAL backend call: logs in, then fetches the signed-in user's
  /// profile (login alone doesn't return it). On success, bridges the
  /// result into the existing local Account/UserRole model so the rest
  /// of the app keeps working unchanged.
  Future<String?> signIn({required String email, required String password}) async {
    try {
      await _authService.login(email: email, password: password);
      final profile = await _authService.getCurrentUser();

      currentAccount = Account(
        name: profile.fullName,
        email: profile.email,
        password: password,
        role: _roleFromString(profile.role),
      );
      currentRole = _roleFromString(profile.role);
      await loadCategories();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }
  /// pang shortcut sa login kasi tinatamad na ko mag type all the time
  void devQuickLogin(UserRole role) {
    final testEmail = 'test.${role.name}@dev.local';
    var account = _accounts.where((a) => a.email == testEmail).firstOrNull;
    account ??= Account(
      name: 'Test ${role.name[0].toUpperCase()}${role.name.substring(1)}',
      email: testEmail,
      password: 'dev',
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

  void signOut() {
    currentAccount = null;
    currentRole = null;
    notifyListeners();
  }
}