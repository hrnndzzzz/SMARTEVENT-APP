import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_colors.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/theme/module_identity.dart';

/// What the dashboard says about itself, and in what colours.
///
/// Reported from a phone, looking at the four tiles and the chart
/// under them: the analytics is tiny, the numbers are not the same
/// size, the money bar is not accurate, and there are still colours in
/// here that belong to no theme.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ChangeNotifierProvider(create: (_) => SfxPlayer()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(accent: app.themeColor),
      home: const HomeScreen(),
    ),
  );

  /// The budget figure starts covered, so a test about the figure or
  /// the bar has to uncover it first. The eye is the only way in, which
  /// is also the point of it.
  Future<void> reveal(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the budget tile agrees with itself', () {
    testWidgets('the bar draws what is left, not what is spent', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      addTearDown(app.dispose);

      await tester.pumpWidget(host(app));
      await tester.pump(const Duration(milliseconds: 400));
      await reveal(tester);

      final allocated = app.totalAllocated;
      expect(allocated, greaterThan(0), reason: 'the demo has no budget');
      final expected = app.remainingBalance / allocated;

      final bars = tester.widgetList<BrutProgressBar>(
        find.byType(BrutProgressBar),
      );
      expect(bars, isNotEmpty);
      expect(
        bars.first.value,
        closeTo(expected, 0.001),
        reason:
            'the tile says "of X left" and the bar filled with '
            'spending, so the bar and the sentence above it read as '
            'opposites',
      );
      // And the reading it replaced, so a revert is caught here.
      final spentShare = app.totalExpended / allocated;
      expect(bars.first.value, isNot(closeTo(spentShare, 0.001)));
    });
  });

  group('one size for the four figures', () {
    test('short figures keep the design size', () {
      expect(sharedFigureSize(const ['3', '1', '2'], 300), 26);
    });

    test('a long one brings all of them down together', () {
      // The point is not the exact number: it is that there is one
      // number. Four tiles scaling independently is what put two
      // sizes in one grid.
      final size = sharedFigureSize(const ['3', '1', 'P1,250,000'], 80);
      expect(size, lessThan(26));
      expect(
        sharedFigureSize(const ['3'], 80, cap: size),
        size,
        reason: 'the short figure must take the shared size, not its own',
      );
    });

    test('it never grows a figure past the design size', () {
      expect(sharedFigureSize(const ['3'], 10000), 26);
    });

    test('and a width of nothing does not collapse it', () {
      // A LayoutBuilder can hand back a zero width for one frame.
      expect(sharedFigureSize(const ['3'], 0), 26);
      expect(sharedFigureSize(const [], 300), 26);
    });
  });

  group('blue and orange, and nothing else', () {
    // SmartEvent is blue and orange — CITE's two, and the logo's two.
    // The module set had drifted to a purple Inventory at 271 degrees
    // and a green Admin at 142, which belong to neither.
    double hue(Color c) => HSLColor.fromColor(c).hue;
    double saturation(Color c) => HSLColor.fromColor(c).saturation;

    test('every module is blue, orange, a status, or a grey', () {
      for (final module in Module.values) {
        for (final colour in [module.color, module.colorDark]) {
          if (saturation(colour) < 0.15) continue; // Search is a grey.
          if (module == Module.flagged) continue; // Red is a status.
          final h = hue(colour);
          final blue = h >= 195 && h <= 245;
          final orange = h >= 15 && h <= 45;
          expect(
            blue || orange,
            isTrue,
            reason:
                '${module.name} is at ${h.toStringAsFixed(0)} degrees, '
                'which is neither the blue family nor the orange one',
          );
        }
      }
    });

    test('the three blues are told apart, and none collides', () {
      final blues = [
        Module.events,
        Module.inventory,
        Module.admin,
      ].map((m) => hue(m.color)).toList()..sort();
      for (var i = 1; i < blues.length; i++) {
        expect(
          blues[i] - blues[i - 1],
          greaterThanOrEqualTo(10),
          reason: 'two blue blocks sit on top of each other',
        );
      }
    });

    test('and they carry one saturation, not three', () {
      // Equal luminance alone still let a vivid block sit beside a
      // muted one and read as the louder of the two.
      for (final module in [Module.events, Module.inventory, Module.admin]) {
        expect(
          saturation(module.color),
          closeTo(saturation(Module.events.color), 0.02),
          reason: '${module.name} is a different strength of blue',
        );
      }
    });

    test('Flagged is still the status red it shares with a rejection', () {
      expect(hue(Module.flagged.color), lessThan(15));
      expect(saturation(Module.flagged.color), greaterThan(0.3));
    });

    test('and nothing moved off the band while being repainted', () {
      for (final module in Module.values) {
        expect(
          module.color.computeLuminance(),
          lessThanOrEqualTo(AppColors.bandLuminance + 0.001),
          reason: '${module.name} is brighter than the band',
        );
      }
    });
  });
}
