import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/academic.dart';
import 'package:smartevent/state/app_state.dart';

/// Event status and academic labelling.
///
/// `draft` and `completed` used to collapse into "pending adviser", so an
/// unsubmitted draft looked like it was sitting in someone's review queue
/// and a finished event looked unreviewed.
void main() {
  group('status semantics', () {
    test('draft is not pending and not resolved', () {
      const status = EventApprovalStatus.draft;
      expect(status.isDraft, isTrue);
      expect(status.isPending, isFalse);
      expect(status.isResolved, isFalse);
    });

    test('both pending stages count as pending and stay distinct', () {
      expect(EventApprovalStatus.pendingAdviser.isPending, isTrue);
      expect(EventApprovalStatus.pendingAdmin.isPending, isTrue);
      expect(
        EventApprovalStatus.pendingAdviser,
        isNot(EventApprovalStatus.pendingAdmin),
      );
    });

    test('only draft and rejected are editable', () {
      expect(EventApprovalStatus.draft.isEditable, isTrue);
      expect(EventApprovalStatus.rejected.isEditable, isTrue);
      expect(EventApprovalStatus.pendingAdviser.isEditable, isFalse);
      expect(EventApprovalStatus.pendingAdmin.isEditable, isFalse);
      expect(EventApprovalStatus.approved.isEditable, isFalse);
      expect(EventApprovalStatus.completed.isEditable, isFalse);
    });

    test('approved, rejected and completed are resolved', () {
      expect(EventApprovalStatus.approved.isResolved, isTrue);
      expect(EventApprovalStatus.rejected.isResolved, isTrue);
      expect(EventApprovalStatus.completed.isResolved, isTrue);
    });

    test('every status has its own label', () {
      final labels = {
        for (final status in EventApprovalStatus.values)
          EventItem(
            title: 't',
            org: 'o',
            date: 'd',
            budget: 'b',
            status: status,
          ).statusLabel,
      };
      expect(labels.length, EventApprovalStatus.values.length);
    });
  });

  group('academic labelling', () {
    EventItem event({
      String? schoolYear,
      Semester? semester,
      EventScope? scope,
    }) =>
        EventItem(
          title: 't',
          org: 'o',
          date: 'd',
          budget: 'b',
          schoolYear: schoolYear,
          semester: semester,
          eventScope: scope,
        );

    test('a fully set event reads as year, semester and scope', () {
      final item = event(
        schoolYear: '2026-2027',
        semester: Semester.first,
        scope: EventScope.departmental,
      );

      expect(item.hasIncompleteAcademicMetadata, isFalse);
      expect(item.academicLabel, '2026-2027 · 1st sem · Departmental');
    });

    test('a legacy row with nothing set says so', () {
      final item = event();

      expect(item.hasIncompleteAcademicMetadata, isTrue);
      expect(item.academicLabel, 'No school year set');
    });

    test('a partially set row shows what is known and still reads incomplete',
        () {
      final item = event(schoolYear: '2026-2027');

      expect(item.hasIncompleteAcademicMetadata, isTrue);
      expect(item.academicLabel, '2026-2027');
    });
  });
}
