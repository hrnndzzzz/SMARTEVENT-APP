import 'package:flutter/material.dart';

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

class PendingRequest {
  final String title;
  final String org;
  final String amount;
  final String type;

  PendingRequest({
    required this.title,
    required this.org,
    required this.amount,
    this.type = 'Budget',
  });
}

class EventItem {
  String title;
  String org;
  String date;
  String venue;
  String budget;
  String attendees;
  int approvalStep;
  String get statusLabel => switch (approvalStep) {
    0 => 'Submitted',
    1 => 'Under Review',
    2 => 'Budget Approved',
    _ => 'Active',
  };

  EventItem({
    required this.title,
    required this.org,
    required this.date,
    required this.venue,
    required this.budget,
    required this.attendees,
    this.approvalStep = 0,
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

  AppNotification({
    required this.icon,
    required this.tagColor,
    required this.title,
    required this.body,
    required this.time,
    this.unread = true,
    this.destination = NotifDestination.none,
  });
}

class Account {
  final String name;
  final String email;
  final String password;

  Account({required this.name, required this.email, required this.password});
}
class ExpenseEntry {
  final String vendor;
  final double amount;
  final String category;

  ExpenseEntry({required this.vendor, required this.amount, required this.category});
}

class AppState extends ChangeNotifier {
  double totalAllocated = 5000.00;
  double totalExpended = 2150.00;

  double get remainingBalance => totalAllocated - totalExpended;

  final List<ExpenseEntry> expenses = [
    ExpenseEntry(vendor: 'Fresh Campus Catering', amount: 950.00, category: 'Catering'),
    ExpenseEntry(vendor: 'CITE Auditorium Rental', amount: 650.00, category: 'Venue'),
    ExpenseEntry(vendor: 'National Bookstore', amount: 350.00, category: 'Equipment'),
    ExpenseEntry(vendor: 'Print Shop Flyers', amount: 200.00, category: 'Marketing'),
  ];

  /// Legacy string log kept for the Dashboard's "Recent activity" list.
  List<String> get expenseLog =>
      expenses.map((e) => '${e.vendor} · -₱${e.amount.toStringAsFixed(2)}').toList();

  static const List<String> expenseCategories = ['Equipment', 'Venue', 'Catering', 'Marketing'];

  void logExpense(String vendor, double amount, {String category = 'Equipment'}) {
    totalExpended += amount;
    expenses.insert(0, ExpenseEntry(vendor: vendor, amount: amount, category: category));
    addNotification(AppNotification(
      icon: Icons.receipt_long_outlined,
      tagColor: const Color(0xFF2B3A67),
      title: 'Expense logged',
      body: '$vendor (₱${amount.toStringAsFixed(2)}) recorded.',
      time: 'Just now',
      destination: NotifDestination.dashboard,
    ));
    notifyListeners();
  }

  /// Category -> total spent, computed live from [expenses].
  Map<String, double> get spendByCategory {
    final totals = {for (final c in expenseCategories) c: 0.0};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return totals;
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
      ));
    }
    notifyListeners();
  }

  void restockItem(InventoryItem item, {int amount = 5}) {
    item.qty += amount;
    inventoryLog.insert(0, '${item.name} — restocked +$amount · just now');
    notifyListeners();
  }

  final List<PendingRequest> pendingRequests = [
    PendingRequest(
      title: 'Leadership Summit 2026 — Budget Proposal',
      org: 'Engineering Soc.',
      amount: '₱8,200.00',
      type: 'Budget',
    ),
    PendingRequest(
      title: 'CITE Sports Fest — Cash Advance',
      org: 'CITE Student Council',
      amount: '₱1,500.00',
      type: 'Advance',
    ),
  ];

  final List<PendingRequest> handledRequests = [];

  void decideRequest(PendingRequest req, {required bool approved}) {
    pendingRequests.remove(req);
    handledRequests.insert(0, req);
    addNotification(AppNotification(
      icon: approved ? Icons.check_circle_outline : Icons.cancel_outlined,
      tagColor: approved ? const Color(0xFF3F8272) : const Color(0xFFC1503D),
      title: approved ? 'Request approved' : 'Request rejected',
      body: '${req.title} — ${req.org}',
      time: 'Just now',
    ));
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
      approvalStep: 3,
    ),
    EventItem(
      title: 'Leadership Summit 2026',
      org: 'CITE Student Council',
      date: 'Nov 20, 2026',
      venue: 'CITE Auditorium',
      budget: '₱8,200.00',
      attendees: '120 (expected)',
      approvalStep: 1,
    ),
  ];

  void addEvent(EventItem event) {
    events.insert(0, event);
    addNotification(AppNotification(
      icon: Icons.event_outlined,
      tagColor: const Color(0xFFE8A33D),
      title: 'Event proposal submitted',
      body: '${event.title} is now awaiting review.',
      time: 'Just now',
      destination: NotifDestination.events,
    ));
    notifyListeners();
  }

  /// Call after mutating an EventItem's fields directly to refresh listeners.
  void updateEvent() {
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
    ),
    AppNotification(
      icon: Icons.fact_check_outlined,
      tagColor: const Color(0xFFE8A33D),
      title: 'Pending approval: Leadership Summit 2026',
      body: 'Budget proposal from Engineering Soc. awaiting your review.',
      time: '2 hrs ago',
    ),
    AppNotification(
      icon: Icons.event_outlined,
      tagColor: const Color(0xFF3F8272),
      title: 'Upcoming: CITE Sports Fest',
      body: 'Event starts in 3 days. Final headcount due tomorrow.',
      time: '5 hrs ago',
      unread: false,
      destination: NotifDestination.events,
    ),
  ];

  void addNotification(AppNotification n) {
    notifications.insert(0, n);
  }

  int get unreadNotificationCount => notifications.where((n) => n.unread).length;

  void markAllNotificationsRead() {
    for (final n in notifications) {
      n.unread = false;
    }
    notifyListeners();
  }

  void markRead(AppNotification n) {
    n.unread = false;
    notifyListeners();
  }

  final List<Account> _accounts = [
    Account(name: 'Juan Dela Cruz', email: 'juan.delacruz@lcup.edu.ph', password: 'password123'),
  ];

  Account? currentAccount;

  bool signUp({required String name, required String email, required String password}) {
    if (_accounts.any((a) => a.email == email)) return false;
    final account = Account(name: name, email: email, password: password);
    _accounts.add(account);
    currentAccount = account;
    notifyListeners();
    return true;
  }

  bool signIn({required String email, required String password}) {
    final match = _accounts.where((a) => a.email == email && a.password == password);
    if (match.isEmpty) return false;
    currentAccount = match.first;
    notifyListeners();
    return true;
  }

  void signOut() {
    currentAccount = null;
    notifyListeners();
  }
}