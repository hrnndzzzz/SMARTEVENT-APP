import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What has been swiped away, on this phone.
///
/// Dismissing is a local act: the server knows whether a notice has been
/// read, because that is a fact about the account, but it has no opinion
/// about whether you want to keep seeing it. Another phone keeps its own
/// list, which is the honest behaviour — a notice you cleared on your
/// own handset was not cleared for anybody else.
///
/// Kept per account, so signing in as someone else does not inherit the
/// last person's hidden notices.
class NoticeShelf extends ChangeNotifier {
  NoticeShelf();

  String _accountId = '';
  final Set<String> _dismissed = {};

  /// Whether [id] has been swiped away and should stay hidden.
  bool isDismissed(String id) => _dismissed.contains(id);

  int get dismissedCount => _dismissed.length;

  String _key(String accountId) => 'notices_dismissed_$accountId';

  /// Points the shelf at an account and reads what it has hidden.
  /// Clears first, so a slow read cannot leak one account's list into
  /// another's.
  Future<void> openFor(String accountId) async {
    _accountId = accountId;
    _dismissed.clear();
    notifyListeners();
    if (accountId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_accountId != accountId) return; // Someone switched mid-read.
      _dismissed.addAll(prefs.getStringList(_key(accountId)) ?? const []);
    } catch (_) {
      // An unreadable store hides nothing, which is the safe direction:
      // showing a notice twice beats losing one.
    }
    notifyListeners();
  }

  Future<void> dismiss(String id) async {
    if (!_dismissed.add(id)) return;
    notifyListeners();
    await _write();
  }

  Future<void> dismissAll(Iterable<String> ids) async {
    final before = _dismissed.length;
    _dismissed.addAll(ids);
    if (_dismissed.length == before) return;
    notifyListeners();
    await _write();
  }

  /// Lets a notice back in. Used when an id is reissued because the
  /// thing behind it happened again.
  Future<void> restore(String id) async {
    if (!_dismissed.remove(id)) return;
    notifyListeners();
    await _write();
  }

  Future<void> clear() async {
    if (_dismissed.isEmpty) return;
    _dismissed.clear();
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    if (_accountId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key(_accountId), _dismissed.toList());
    } catch (_) {
      // Hidden for this run regardless.
    }
  }
}
