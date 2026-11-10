import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_colors.dart';

/// Choosing the colour the app wears.
///
/// The accent belongs to the account's department. This overrides it on
/// one phone, and the thing that must stay true is that it overrides
/// nothing else: the department is still what the records belong to.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppSettings> settings() async {
    final s = AppSettings();
    await s.restore();
    return s;
  }

  test('nothing is chosen to begin with', () async {
    expect((await settings()).accent, isNull);
  });

  test('a choice sticks across a restart', () async {
    await (await settings()).setAccent(Department.cithm);

    final next = await settings();

    expect(next.accent, Department.cithm);
  });

  test('going back leaves nothing stored, not a sentinel', () async {
    final s = await settings();
    await s.setAccent(Department.case_);

    await s.setAccent(null);

    expect(s.accent, isNull);
    expect(
      (await settings()).accent,
      isNull,
      reason:
          '"never chose" and "chose to go back" are the same state, '
          'and must survive a restart as the same state',
    );
  });

  test('every option can carry ink, and none of them means trouble', () {
    for (final option in Department.values) {
      expect(
        option.color,
        isNot(AppColors.coral),
        reason:
            '${option.label}: coral means "a problem" everywhere else '
            'in the app, so no department and no choice may wear it',
      );
    }
  });

  test('the department keeps its own colour whatever is chosen', () async {
    final s = await settings();

    await s.setAccent(Department.camp);

    expect(
      Department.cite.color,
      isNot(Department.camp.color),
      reason:
          'the override is read at the top of the widget tree; it must '
          'not reach into the department palette itself',
    );
  });
}
