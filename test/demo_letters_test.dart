import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';

/// Reading proposal letters is the SDS Staff role's only permission, so
/// an empty list made the whole role look broken: signing in as the
/// office landed on "No letters yet" with nothing else it could reach.
void main() {
  test('the office has letters to read', () {
    final app = AppState()..enterDemo(role: UserRole.sdsStaff);

    expect(app.letters, isNotEmpty);
  });

  test('every letter belongs to an event the demo has', () {
    // A letter pointing at an event that is not there is worse than no
    // letter: the list reads fine and the link goes nowhere.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final ids = {for (final e in app.events) e.remoteId};

    for (final letter in app.letters) {
      expect(
        ids,
        contains(letter.eventId),
        reason: '${letter.title} points at a missing event',
      );
    }
  });

  test('both document kinds are represented', () {
    // The card picks its icon from the extension, so a list of nothing
    // but PDFs never shows the other branch.
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    expect(app.letters.where((l) => l.looksLikePdf), isNotEmpty);
    expect(app.letters.where((l) => !l.looksLikePdf), isNotEmpty);
  });

  test('no letter claims a link that would not open', () {
    // The screen shows this as text to copy and never fetches it. An
    // https URL to a host that does not exist reads as a working link.
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    for (final letter in app.letters) {
      expect(letter.documentUrl, isNot(startsWith('http')));
    }
  });
}
