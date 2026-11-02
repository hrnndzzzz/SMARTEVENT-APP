import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/sap/sap_form_fields.dart';
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

  group('a choice that cannot be changed', () {
    testWidgets('single choice: every chip is disabled and reads that way', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var changed = 0;
      await tester.pumpWidget(single(enabled: false, onChanged: (_) => changed++));

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
      await tester.pumpWidget(multi(enabled: false, onChanged: (_) => changed++));

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

    testWidgets('looks flat and muted next to an enabled one', (tester) async {
      await tester.pumpWidget(single(enabled: false));
      final palette = BrutPalette.lightPalette;

      // The chosen chip would carry the accent and a shadow if it could be
      // changed; locked, it takes the disabled fill and loses the shadow.
      final box =
          tester
                  .widget<AnimatedContainer>(
                    find
                        .descendant(
                          of: find.widgetWithText(BrutChip, 'Yes'),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.color, palette.line);
      expect(box.boxShadow, anyOf(isNull, isEmpty));
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
}
