import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/brut.dart';

/// Guards the one thing the three-page shell could plausibly break: a
/// sideways drag meant for something inside a screen flipping the whole
/// shell to another page instead.
///
/// Every horizontally scrolling thing in the app — the filter chips on
/// Events, Receipts, Inventory and Search, and the table in the export
/// preview — lives on a pushed route rather than on one of the three
/// pages. A pushed route is a sibling of the PageView in the Navigator's
/// overlay, not a descendant, so the two never share a gesture arena.
/// This asserts that rather than trusting it.
void main() {
  testWidgets('a sideways drag inside a pushed screen does not change the '
      'shell page', (tester) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: controller,
            children: const [
              Center(child: Text('menu')),
              _PusherPage(),
              Center(child: Text('events')),
            ],
          ),
        ),
      ),
    );

    expect(controller.page, 1);

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chips')), findsOneWidget);

    // A long sideways drag, right across the chip row.
    await tester.drag(find.byKey(const Key('chips')), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(
      controller.page,
      1,
      reason: 'the shell must stay on the page it was on',
    );
    expect(
      find.byKey(const Key('chips')),
      findsOneWidget,
      reason: 'and the pushed screen must still be up',
    );
  });
}

class _PusherPage extends StatelessWidget {
  const _PusherPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: Center(
                child: SizedBox(
                  key: const Key('chips'),
                  height: 40,
                  child: BrutChipBar(
                    children: [
                      for (var i = 0; i < 12; i++)
                        BrutChip(
                          label: 'Filter $i',
                          selected: i == 0,
                          onTap: () {},
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        child: const Text('push'),
      ),
    );
  }
}
