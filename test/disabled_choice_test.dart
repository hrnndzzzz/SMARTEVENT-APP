import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_cover_screen.dart';
import 'package:smartevent/screens/sap/sap_form_fields.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part2_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/theme/palette.dart';

/// Stands in for the sound player, which would reach for a platform audio
/// channel a widget test does not have, and keeps what it was asked to play.
class _HeardTaps extends ChangeNotifier implements SfxPlayer {
  final heard = <Sfx>[];

  @override
  void play(Sfx sound) => heard.add(sound);

  @override
  bool get enabled => true;

  @override
  Future<void> load() async {}

  @override
  Future<void> setEnabled(bool value) async {}
}

/// A tick box the screen will not let you change has to look and read that
/// way. The SAP choices once answered a locked form with a chip whose tap did
/// nothing: it looked like every other chip, and a screen reader offered it as
/// one, so a Moderator or Dean reading a proposal pressed it and nothing
/// happened.
void main() {
  late _HeardTaps sound;

  Widget host(Widget child) => ChangeNotifierProvider<SfxPlayer>.value(
    value: sound,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  setUp(() => sound = _HeardTaps());

  Widget single({required bool enabled, ValueChanged<String?>? onChanged}) =>
      host(
        SapSingleChoice<String>(
          label: 'Answer',
          options: const ['Yes', 'No'],
          labelOf: (x) => x,
          value: 'Yes',
          onChanged: onChanged ?? (_) {},
          enabled: enabled,
        ),
      );

  Widget multi({
    required bool enabled,
    ValueChanged<List<String>>? onChanged,
  }) => host(
    SapMultiChoice<String>(
      label: 'Answers',
      options: const ['Yes', 'No'],
      labelOf: (x) => x,
      selected: const ['Yes'],
      onChanged: onChanged ?? (_) {},
      enabled: enabled,
    ),
  );

  /// Every chip's surface, in order.
  List<BrutSurface> surfaces(WidgetTester tester) => tester
      .widgetList<BrutSurface>(
        find.descendant(
          of: find.byType(BrutChip),
          matching: find.byType(BrutSurface),
        ),
      )
      .toList();

  /// What the platform's accessibility layer is told about the chip that
  /// says [label].
  SemanticsData semanticsOf(WidgetTester tester, String label) =>
      tester.getSemantics(find.text(label)).getSemanticsData();

  /// How the chip that says [label] is drawn.
  BoxDecoration decorationOf(WidgetTester tester, String label) =>
      tester
              .widget<AnimatedContainer>(
                find
                    .descendant(
                      of: find.widgetWithText(BrutChip, label),
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

  FontWeight? weightOf(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.fontWeight;

  group('a choice that cannot be changed', () {
    testWidgets('single choice: every chip is disabled and reads that way', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var changed = 0;
      await tester.pumpWidget(
        single(enabled: false, onChanged: (_) => changed++),
      );

      expect(surfaces(tester), hasLength(2));
      expect(surfaces(tester).map((s) => s.enabled), everyElement(isFalse));
      for (final label in ['Yes', 'No']) {
        final data = semanticsOf(tester, label);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        // Its own node, not the whole row merged into one.
        expect(data.label, label);
      }

      await tester.tap(find.text('No'));
      await tester.tap(find.text('Yes'));
      await tester.pump();
      expect(changed, 0);
      expect(sound.heard, isEmpty, reason: 'no tap sound for a dead chip');
      handle.dispose();
    });

    testWidgets('multiple choice: every chip is disabled and reads that way', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var changed = 0;
      await tester.pumpWidget(
        multi(enabled: false, onChanged: (_) => changed++),
      );

      expect(surfaces(tester), hasLength(2));
      expect(surfaces(tester).map((s) => s.enabled), everyElement(isFalse));
      for (final label in ['Yes', 'No']) {
        final data = semanticsOf(tester, label);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        // Its own node, not the whole row merged into one.
        expect(data.label, label);
      }

      await tester.tap(find.text('No'));
      await tester.pump();
      expect(changed, 0);
      expect(sound.heard, isEmpty);
      handle.dispose();
    });

    testWidgets('a chosen chip loses the accent fill and shadow', (
      tester,
    ) async {
      await tester.pumpWidget(single(enabled: true));
      final live = decorationOf(tester, 'Yes');
      await tester.pumpWidget(single(enabled: false));
      final locked = decorationOf(tester, 'Yes');

      expect(live.color, isNot(BrutPalette.lightPalette.line));
      expect(live.boxShadow, isNotEmpty);
      expect(locked.color, BrutPalette.lightPalette.line);
      expect(locked.boxShadow, anyOf(isNull, isEmpty));
    });

    testWidgets('the chosen answer is still told from the rest', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(single(enabled: false));
      final palette = BrutPalette.lightPalette;

      // Beside "No", locked "Yes" keeps an ink outline and the heavier
      // weight; "No" has the muted outline and steps down to regular.
      expect(decorationOf(tester, 'Yes').border!.top.color, palette.ink);
      expect(decorationOf(tester, 'No').border!.top.color, palette.muted);
      expect(weightOf(tester, 'Yes'), FontWeight.w700);
      expect(weightOf(tester, 'No'), FontWeight.w400);

      // And a screen reader is told which one it is.
      expect(
        semanticsOf(tester, 'Yes').flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        semanticsOf(tester, 'No').flagsCollection.isSelected,
        isNot(Tristate.isTrue),
      );
      handle.dispose();
    });
  });

  group('a choice that can be changed', () {
    testWidgets('single choice: chips are enabled and select on tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final picked = <String?>[];
      await tester.pumpWidget(single(enabled: true, onChanged: picked.add));

      expect(surfaces(tester).map((s) => s.enabled), everyElement(isTrue));
      expect(
        semanticsOf(tester, 'No').flagsCollection.isEnabled,
        isNot(Tristate.isFalse),
      );

      await tester.tap(find.text('No'));
      // Tapping the chosen one again clears it.
      await tester.tap(find.text('Yes'));
      expect(picked, ['No', null]);
      expect(sound.heard, [Sfx.tap, Sfx.tap]);
      handle.dispose();
    });

    testWidgets('multiple choice: chips are enabled and toggle on tap', (
      tester,
    ) async {
      final picked = <List<String>>[];
      await tester.pumpWidget(multi(enabled: true, onChanged: picked.add));

      expect(surfaces(tester).map((s) => s.enabled), everyElement(isTrue));

      await tester.tap(find.text('No'));
      await tester.tap(find.text('Yes'));
      expect(picked, [
        ['Yes', 'No'],
        <String>[],
      ]);
    });
  });

  // These three put a chip of their own on a locked form. Each used to pass an
  // empty callback, so a locked one kept its accent, played the tap sound and
  // was read as a live button beside the choices above that had gone grey.
  group('the chips a locked screen adds of its own', () {
    Future<void> openLocked(WidgetTester tester, Widget screen) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<SfxPlayer>.value(
          value: sound,
          child: MaterialApp(theme: AppTheme.light(), home: screen),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// A proposal waiting on the SDS Office, which its proposer cannot change.
    SapForm locked({SapSetting? setting, bool ticked = false}) =>
        SapForm(eventId: 'e1')
          ..updateDetails((d) => d.copyWith(setting: setting))
          ..setSupportRequests([
            if (ticked)
              const SapSupportRequest(type: SapSupportType.microphone),
          ])
          ..seedLocally(state: SapState.pendingReview);

    void expectDead(WidgetTester tester, String label) {
      final chip = find.widgetWithText(BrutChip, label);
      expect(chip, findsOneWidget);
      expect(tester.widget<BrutChip>(chip).onTap, isNull);
      expect(
        tester
            .widget<BrutSurface>(
              find.descendant(of: chip, matching: find.byType(BrutSurface)),
            )
            .enabled,
        isFalse,
      );
    }

    testWidgets('the cover: off-campus acknowledgement', (tester) async {
      final form = locked(setting: SapSetting.offCampus);
      await openLocked(tester, SapCoverScreen(form: form, onBegin: (_) {}));

      expectDead(tester, 'I acknowledge these');
      await tester.tap(find.text('I acknowledge these'), warnIfMissed: false);
      expect(form.details.offCampusAgreement, isFalse);
      expect(sound.heard, isEmpty);
    });

    testWidgets('Part 1: off-campus acknowledgement', (tester) async {
      // Part 1 only asks for it when it was the screen that asked for the
      // setting, so the setting arrives after it opened.
      final form = locked();
      await openLocked(tester, SapPart1Screen(form: form));
      form.updateDetails((d) => d.copyWith(setting: SapSetting.offCampus));
      await tester.pumpAndSettle();

      expectDead(tester, 'I acknowledge the off-campus requirements');
    });

    testWidgets('Part 2: a ticked support type', (tester) async {
      final form = locked(ticked: true);
      await openLocked(tester, SapPart2Screen(form: form));

      expectDead(tester, SapSupportType.microphone.label);
      await tester.tap(
        find.widgetWithText(BrutChip, SapSupportType.microphone.label),
        warnIfMissed: false,
      );
      expect(form.supportRequests, hasLength(1));
      expect(sound.heard, isEmpty);
    });
  });
}
