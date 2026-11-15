import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/brand_pill.dart';
import 'package:smartevent/widgets/connection_banner.dart';

/// The connection used to be announced in a pill that dropped over the
/// header for three seconds. It is the header now: the brand pill
/// extends to make room for the word and takes the colour of what
/// happened, then goes back to the department accent.
void main() {
  Widget host(Reachability reach, {bool withPill = true}) =>
      ChangeNotifierProvider<Reachability>.value(
        value: reach,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ConnectionBanner(
            child: Scaffold(
              body: SafeArea(
                child: Row(
                  children: [if (withPill) const BrandPill(), const Spacer()],
                ),
              ),
            ),
          ),
        ),
      );

  double pillWidth(WidgetTester tester) =>
      tester.getSize(find.byType(BrandPill)).width;

  Color pillFill(WidgetTester tester) => tester
      .widgetList<BrutSurface>(
        find.descendant(
          of: find.byType(BrandPill),
          matching: find.byType(BrutSurface),
        ),
      )
      .first
      .fill!;

  Color tone(WidgetTester tester, BrutTone t) =>
      t.fill(tester.element(find.byType(BrandPill)));

  /// The announcement is made one frame after the build that noticed
  /// it, so the tree is never marked dirty mid-layout.
  Future<void> settleAnnouncement(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Runs the hold out, so the message has gone and its timer with it.
  ///
  /// Reachability's own 30-second retry has to be stopped inside the
  /// test body too: the framework checks for pending timers before
  /// tearDown callbacks run, so disposing it there is too late.
  Future<void> quiet(WidgetTester tester, Reachability reach) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    reach.dispose();
  }

  testWidgets('the first answer from the server is not news', (tester) async {
    // The rule used to be "anything that is not online", and unknown is
    // not online — so the very first answer, which is what every launch
    // begins with, was announced as a recovery. In the demo, which
    // talks to no server, the wake probe still reached one and the
    // walkthrough opened under a green "Back online".
    final reach = Reachability();
    await tester.pumpWidget(host(reach));
    await tester.pumpAndSettle();

    final resting = pillWidth(tester);

    reach.report(reachable: true);
    await settleAnnouncement(tester);

    expect(find.text('Back online'), findsNothing);
    expect(pillWidth(tester), resting);
    reach.dispose();
  });

  testWidgets('losing the server extends the bar and reddens it', (
    tester,
  ) async {
    final reach = Reachability()..report(reachable: true);
    await tester.pumpWidget(host(reach));
    await tester.pumpAndSettle();

    final resting = pillWidth(tester);
    final restingFill = pillFill(tester);

    reach.report(reachable: false);
    await settleAnnouncement(tester);

    expect(find.text('No connection'), findsOneWidget);
    expect(
      pillWidth(tester),
      greaterThan(resting),
      reason: 'the bar makes room rather than something appearing over it',
    );
    expect(pillFill(tester), isNot(restingFill));
    expect(pillFill(tester), tone(tester, BrutTone.coral));

    // And back, on its own, a few seconds later.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsNothing);
    expect(pillWidth(tester), resting);
    expect(pillFill(tester), restingFill);
    reach.dispose();
  });

  testWidgets('a retry that fails does not say it again', (tester) async {
    // The real thirty-second probe, not a flag: while the server is
    // down it goes offline → reconnecting → offline, and each return
    // used to count as the server dropping again. Told once means
    // once, not twice a minute for as long as it lasts.
    final reach = Reachability(
      httpClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        throw http.ClientException('down');
      }),
    )..report(reachable: true);

    await tester.pumpWidget(host(reach));
    await tester.pumpAndSettle();

    reach.report(reachable: false);
    await settleAnnouncement(tester);
    expect(find.text('No connection'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('No connection'), findsNothing);

    // Started, not awaited: the tree has to be built while the probe
    // is in flight, or the retry passes through unseen and this would
    // be green for the wrong reason.
    final probe = reach.wake();
    await tester.pump();
    await tester.pump();
    expect(reach.state, Reachable.reconnecting);

    await tester.pump(const Duration(seconds: 3));
    await probe;
    await settleAnnouncement(tester);

    expect(reach.state, Reachable.offline);
    expect(find.text('No connection'), findsNothing);
    await quiet(tester, reach);
  });

  testWidgets('coming back is green, and only from having been away', (
    tester,
  ) async {
    final reach = Reachability()..report(reachable: false);
    await tester.pumpWidget(host(reach));
    await tester.pumpAndSettle();
    // Let the "No connection" announcement pass.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    reach.report(reachable: true);
    await settleAnnouncement(tester);

    expect(find.text('Back online'), findsOneWidget);
    expect(pillFill(tester), tone(tester, BrutTone.mint));
    await quiet(tester, reach);
  });

  testWidgets('the floating pill stays away when the bar has it', (
    tester,
  ) async {
    final reach = Reachability()..report(reachable: true);
    await tester.pumpWidget(host(reach));
    await tester.pumpAndSettle();

    reach.report(reachable: false);
    await settleAnnouncement(tester);

    // One message, in one place. Two things saying it at once is what
    // moving it into the header was supposed to stop.
    expect(find.text('No connection'), findsOneWidget);
    await quiet(tester, reach);
  });

  testWidgets('with no bar to say it, the floating pill still does', (
    tester,
  ) async {
    // Welcome and Sign in have no header, and they are exactly where a
    // cold server is waited on.
    final reach = Reachability()..report(reachable: true);
    await tester.pumpWidget(host(reach, withPill: false));
    await tester.pumpAndSettle();

    reach.report(reachable: false);
    await settleAnnouncement(tester);

    expect(find.text('No connection'), findsOneWidget);
    await quiet(tester, reach);
  });

  testWidgets('a pill with nothing watching draws itself plain', (
    tester,
  ) async {
    // A widget test rendering one screen has no reason to wire up
    // connectivity, and the header must not be the thing that brings a
    // screen down.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SafeArea(child: BrandPill())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SmartEvent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
