import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part2_screen.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/screens/sap/sap_part4_screen.dart';
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/screens/sap/sap_part6_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// With no service the form is local-only, which is exactly the state the
/// screens have to work in until the backend slice lands.
SapForm blankForm() => SapForm(eventId: 'e1');

/// A form wired to a backend that answers 404 for this event's proposal.
///
/// Local-only for a different reason than [blankForm]: there is a server,
/// it is reachable, and it has nothing for this event. The hub has to say
/// which of the two it is rather than blaming the backend either way.
Future<SapForm> formWithAbsentProposal() async {
  final client = MockClient(
    (_) async => http.Response(
      jsonEncode({'detail': 'Not Found'}),
      404,
      headers: {'content-type': 'application/json'},
    ),
  );
  final form = SapForm(
    eventId: 'e1',
    service: SapService(ApiClient(httpClient: client)),
  );
  await form.load();
  return form;
}

Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  testWidgets('the hub lists all six parts', (tester) async {
    await tester.pumpWidget(host(SapFormScreen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.text('Activity Details'), findsOneWidget);
    expect(find.text('School Support'), findsOneWidget);
    expect(find.text('Additional Information'), findsOneWidget);
    expect(find.text('SDS Office Clearance'), findsOneWidget);
    expect(find.text('University Clearance'), findsOneWidget);
    expect(find.text('Evaluation'), findsOneWidget);
  });

  testWidgets('the demo hub says the demo is why, not the backend', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapFormScreen(form: blankForm())));
    await tester.pumpAndSettle();

    // It used to say the backend had no proposal-form routes, which is
    // not true of the demo and is no longer true of the backend.
    expect(find.textContaining('Demo mode'), findsOneWidget);
    expect(find.textContaining('no proposal-form routes'), findsNothing);
  });

  testWidgets('a real backend with no proposal says that instead', (
    tester,
  ) async {
    final form = await formWithAbsentProposal();

    // This one needs the provider: with a service the hub spins on its
    // first frame, and the spinner reads AppSettings for reduced motion.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: host(SapFormScreen(form: form)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('no proposal on the server'), findsOneWidget);
    expect(find.textContaining('Demo mode'), findsNothing);
  });

  testWidgets('Part 1 draws the paper\'s fields', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: blankForm())));
    await tester.pumpAndSettle();

    for (final label in [
      'ACTIVITY TITLE',
      'ORGANIZATION',
      'PROGRAM / COURSE',
      'VENUE',
      'PERSONNEL-IN-CHARGE',
      'ATTIRE',
      'NUMBER OF STUDENTS',
      'RATIONALE',
      'OBJECTIVES',
      'EMERGENCY PLAN',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
    expect(find.text('MODALITY'), findsOneWidget);
    expect(find.text('SETTING'), findsOneWidget);
    expect(find.text('AUGUSTINIAN CORE VALUES'), findsOneWidget);
  });

  testWidgets('Part 1 refuses an end time at or before the start', (
    tester,
  ) async {
    final form = blankForm();
    form.updateDetails(
      (d) => d.copyWith(
        startTime: const SapTime(11, 0),
        endTime: const SapTime(8, 0),
      ),
    );

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('end time has to be after'),
      findsOneWidget,
    );
  });

  testWidgets('Part 1 catches an online setting with a face-to-face modality', (
    tester,
  ) async {
    final form = blankForm();
    form.updateDetails(
      (d) => d.copyWith(
        setting: SapSetting.online,
        modality: SapModality.faceToFace,
      ),
    );

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs the modality to be online'), findsOneWidget);
  });

  testWidgets('Part 1 will not save without a department', (tester) async {
    await tester.pumpWidget(host(SapPart1Screen(form: blankForm())));
    await tester.pumpAndSettle();

    // Nothing could name the department, so the form asks for it.
    expect(find.text('DEPARTMENT TYPE'), findsOneWidget);
    expect(find.text('DEPARTMENT'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text('Fill in the setting, department type and department first.'),
      findsOneWidget,
    );
  });

  testWidgets('Part 1 asks for the setting when the cover was skipped', (
    tester,
  ) async {
    // The six-part list opens Part 1 directly, so nothing chose a setting,
    // and the server refuses the PDF and the submission without one.
    final form = blankForm();
    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('Not chosen'), findsNothing);
    await tester.ensureVisible(find.text('Off campus'));
    await tester.tap(find.text('Off campus'));
    await tester.pumpAndSettle();
    expect(form.details.setting, SapSetting.offCampus);

    final acknowledge = find.text('I acknowledge the off-campus requirements');
    await tester.ensureVisible(acknowledge);
    await tester.tap(acknowledge);
    await tester.pumpAndSettle();
    expect(form.details.offCampusAgreement, isTrue);
  });

  testWidgets('Part 1 keeps a department it already knows off the screen', (
    tester,
  ) async {
    final form = blankForm()
      ..updateDetails(
        (d) => d.copyWith(
          departmentType: 'College',
          department: 'College of Information Technology',
        ),
      );

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('DEPARTMENT'), findsNothing);
    expect(form.details.department, 'College of Information Technology');
  });

  testWidgets('Part 1 caps the long answers at the server\'s limits', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapPart1Screen(form: blankForm())));
    await tester.pumpAndSettle();

    final limits = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.maxLength);
    // Rationale, objectives and emergency plan, as schemas_sap.py has them.
    expect(limits, containsAll([1800, 1200, 600]));
  });

  testWidgets('Part 1 shows the setting but does not ask again', (
    tester,
  ) async {
    // Choosing happens on the cover, before any of this, because it
    // decides what the form will ask for. See sap_cover_test.dart.
    final form = blankForm()
      ..updateDetails((d) => d.copyWith(setting: SapSetting.onCampus));

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('In campus'), findsOneWidget);
    expect(find.text('Off campus'), findsNothing);
    expect(
      find.textContaining('separate CHED compliance workflow'),
      findsNothing,
    );
  });

  testWidgets('Part 1 saves the programme with the details', (tester) async {
    final day = DateTime.now().add(const Duration(days: 60));
    final aggregate = {
      'id': 'p1',
      'event_id': 'e1',
      'state': 'draft',
      'version': 3,
      'revision_no': 0,
      'details': {
        'title': 'Hack the Future',
        'activity_date': day.toIso8601String().substring(0, 10),
        'start_time': '08:00:00',
        'end_time': '11:00:00',
        'setting': 'on_campus',
        // Required since the Save button checks what the server refuses
        // outright: without these the save never leaves the screen.
        'department_type': 'College',
        'department': 'CITE',
      },
      'collections': {
        'program-flow': [
          {'start': '08:00:00', 'end': '11:00:00', 'activity': 'Seminar'},
        ],
      },
    };
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      return http.Response(
        jsonEncode(aggregate),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final form = SapForm(
      eventId: 'e1',
      service: SapService(ApiClient(httpClient: client)),
    );
    await form.load();

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final flow = paths.indexWhere(
      (p) =>
          p.startsWith('PUT ') &&
          p.endsWith('/events/e1/sap-proposal/program-flow'),
    );
    expect(flow, isNot(-1), reason: 'sent: $paths');
    expect(flow, greaterThan(paths.indexWhere((p) => p.startsWith('PATCH'))));
  });

  testWidgets('Part 1 keeps typed text when saved on the way out', (
    tester,
  ) async {
    final day = DateTime.now().add(const Duration(days: 60));
    final aggregate = {
      'id': 'p1',
      'event_id': 'e1',
      'state': 'draft',
      'version': 3,
      'revision_no': 0,
      'details': {
        'title': 'Hack the Future',
        'activity_date': day.toIso8601String().substring(0, 10),
        'start_time': '08:00:00',
        'end_time': '11:00:00',
        'setting': 'on_campus',
      },
      'collections': <String, dynamic>{},
    };
    final patches = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'PATCH') patches.add(request.body);
      return http.Response(
        jsonEncode(aggregate),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final form = SapForm(
      eventId: 'e1',
      service: SapService(ApiClient(httpClient: client)),
    );
    await form.load();

    await tester.pumpWidget(host(SapPart1Screen(form: form)));
    await tester.pumpAndSettle();
    final rationale = find.descendant(
      of: find.ancestor(
        of: find.text('RATIONALE'),
        matching: find.byType(BrutTextField),
      ),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(rationale);
    await tester.enterText(rationale, 'Typed after the last save');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as draft'));
    await tester.pumpAndSettle();

    expect(patches, hasLength(1));
    expect(patches.single, contains('Typed after the last save'));
  });

  testWidgets('Part 2 lists every support type the form has', (tester) async {
    await tester.pumpWidget(host(SapPart2Screen(form: blankForm())));
    await tester.pumpAndSettle();

    for (final type in SapSupportType.values) {
      expect(find.text(type.label), findsOneWidget, reason: type.wireName);
    }
  });

  testWidgets('Part 2 asks for a count once a microphone is ticked', (
    tester,
  ) async {
    final form = blankForm();
    await tester.pumpWidget(host(SapPart2Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('HOW MANY'), findsNothing);

    await tester.ensureVisible(find.text('Microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();

    expect(find.text('HOW MANY'), findsOneWidget);
    expect(form.supportRequests.single.type, SapSupportType.microphone);
  });

  testWidgets('Part 3 totals the budget lines exactly', (tester) async {
    final form = blankForm();
    form.setBudgetItems(const [
      SapBudgetItem(particulars: 'Speaker', amount: '2000.00'),
      SapBudgetItem(particulars: 'Certificates', amount: '300.00'),
      SapBudgetItem(particulars: 'Materials', amount: '200.00'),
    ]);

    await tester.pumpWidget(host(SapPart3Screen(form: form)));
    await tester.pumpAndSettle();

    // Grouped, as the paper writes it and as every other screen does.
    expect(find.text('₱2,500.00'), findsOneWidget);
  });

  testWidgets('Part 3 flags a total that disagrees with Part 1', (
    tester,
  ) async {
    final form = blankForm();
    form.updateDetails((d) => d.copyWith(totalBudget: '2500.00'));
    form.setBudgetItems(const [
      SapBudgetItem(particulars: 'Speaker', amount: '2000.00'),
    ]);

    await tester.pumpWidget(host(SapPart3Screen(form: form)));
    await tester.pumpAndSettle();

    expect(find.textContaining('have to match'), findsOneWidget);
  });

  testWidgets('Part 4 demands a reason for every not-applicable', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapPart4Screen(form: blankForm())));
    await tester.pumpAndSettle();

    // Consent, medical and compliance all default to not applicable, so
    // the first unanswered reason is shown straight away.
    expect(find.textContaining('Say why'), findsOneWidget);
  });

  testWidgets('Part 4 will not claim no interruption when Part 3 lists one', (
    tester,
  ) async {
    final form = blankForm();
    form.setAffectedClasses([
      SapAffectedClass(
        yearLevel: 'BSCpE 3',
        subject: 'Data & Digital',
        classDate: DateTime(2026, 10, 28),
        start: const SapTime(7, 0),
        end: const SapTime(12, 0),
        professor: 'Engr. Glazen Perez',
      ),
    ]);

    await tester.pumpWidget(host(SapPart4Screen(form: form)));
    await tester.pumpAndSettle();

    // Order on screen: consent reason, attachments, medical reason,
    // compliance reason, ratio. The screen shows one problem at a time,
    // so each has to be answered before the next is reached.
    for (final (index, text) in const [
      (0, 'Online activity'),
      (1, 'Program flow and budget'),
      (2, 'Online activity'),
      (3, 'No off-campus travel'),
    ]) {
      await tester.enterText(find.byType(TextField).at(index), text);
      await tester.pumpAndSettle();
    }

    expect(
      find.textContaining('cannot be "none"'),
      findsOneWidget,
    );
  });

  testWidgets('Part 5 shows nine slots in the paper\'s order', (tester) async {
    await tester.pumpWidget(host(SapPart5Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(SapPart5Screen.blankSlots.length, 9);
    expect(find.text('Organization President'), findsOneWidget);
    expect(find.text('Organization Moderator'), findsNWidgets(2));
    expect(find.text('University President'), findsOneWidget);
    // BrutListRow renders meta through MonoLabel, which uppercases.
    expect(find.text('PREPARED BY'), findsOneWidget);
    expect(find.text('APPROVED BY'), findsOneWidget);
  });

  testWidgets('Part 5 never calls a checkpoint a signature', (tester) async {
    await tester.pumpWidget(host(SapPart5Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.textContaining('signed on paper'), findsOneWidget);
    expect(find.text('Sign'), findsNothing);
    expect(find.text('Sign now'), findsNothing);
  });

  testWidgets('Part 5 offers no Record button before submission', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapPart5Screen(form: blankForm())));
    await tester.pumpAndSettle();

    // No slots exist on the server until the first submission, so there
    // is nothing to record against.
    expect(find.text('Record'), findsNothing);
    expect(find.textContaining('open once the proposal is submitted'),
        findsOneWidget);
  });

  testWidgets('Part 6 needs both an outcome and remarks', (tester) async {
    await tester.pumpWidget(host(SapPart6Screen(form: blankForm())));
    await tester.pumpAndSettle();

    expect(find.text('Conducted'), findsOneWidget);
    expect(find.text('Canceled'), findsOneWidget);
    expect(find.text('REMARKS'), findsOneWidget);
  });

  group('part status', () {
    test('an empty form has nothing complete', () {
      final form = blankForm();
      expect(form.completedParts, 0);
      expect(form.statusOf(SapPart.one), SapPartStatus.empty);
    });

    test('Part 5 stays locked until the proposal is submitted', () {
      expect(blankForm().statusOf(SapPart.five), SapPartStatus.locked);
    });

    test('Part 1 reads as started once anything is filled in', () {
      final form = blankForm();
      form.updateDetails((d) => d.copyWith(title: 'Hack the Future'));
      expect(form.statusOf(SapPart.one), SapPartStatus.partial);
    });

    test('Parts 4 to 6 belong to the SDS Office', () {
      expect(SapPart.one.isSdsOnly, isFalse);
      expect(SapPart.three.isSdsOnly, isFalse);
      expect(SapPart.four.isSdsOnly, isTrue);
      expect(SapPart.five.isSdsOnly, isTrue);
      expect(SapPart.six.isSdsOnly, isTrue);
    });
  });

  /// The three choices on the way out, which are squared boxes in the
  /// dialog's body rather than the text links an AlertDialog puts in its
  /// actions row. Moving them is why these two exist: only the save path
  /// had a test, so Cancel and Go back were wired without cover.
  group('leaving a part-filled proposal', () {
    ({SapForm form, List<String> patches}) partOne() {
      final day = DateTime.now().add(const Duration(days: 60));
      final aggregate = {
        'id': 'p1',
        'event_id': 'e1',
        'state': 'draft',
        'version': 3,
        'revision_no': 0,
        'details': {
          'title': 'Hack the Future',
          'activity_date': day.toIso8601String().substring(0, 10),
          'start_time': '08:00:00',
          'end_time': '11:00:00',
          'setting': 'on_campus',
        },
        'collections': <String, dynamic>{},
      };
      final patches = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'PATCH') patches.add(request.body);
        return http.Response(
          jsonEncode(aggregate),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      return (
        form: SapForm(
          eventId: 'e1',
          service: SapService(ApiClient(httpClient: client)),
        ),
        patches: patches,
      );
    }

    testWidgets('Cancel stays, and saves nothing', (tester) async {
      final one = partOne();
      await one.form.load();

      await tester.pumpWidget(host(SapPart1Screen(form: one.form)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Leave this proposal?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Leave this proposal?'), findsNothing);
      expect(find.text('ACTIVITY TITLE'), findsOneWidget, reason: 'still here');
      expect(one.patches, isEmpty, reason: 'Cancel is not a save');
    });

    testWidgets('Go back saves nothing either', (tester) async {
      final one = partOne();
      await one.form.load();

      await tester.pumpWidget(host(SapPart1Screen(form: one.form)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      expect(find.text('Leave this proposal?'), findsNothing);
      expect(
        one.patches,
        isEmpty,
        reason: 'going back is the choice that keeps nothing',
      );
    });
  });
}
