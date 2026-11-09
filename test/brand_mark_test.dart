import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/widgets/brand_mark.dart';

/// The logo, and the fact that it is the logo.
///
/// A placeholder icon is indistinguishable from a real mark at a
/// glance in a screenshot, which is how the generic `groups` icon
/// survived in the welcome screen for months. These assert the thing a
/// screenshot cannot: that the pixels come from the brand file.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('draws the brand artwork, not an icon', (tester) async {
    await tester.pumpWidget(host(const BrandMark()));

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<AssetImage>().having(
        (a) => a.assetName,
        'assetName',
        'assets/brand/mark-on-dark.png',
      ),
    );
  });

  testWidgets('sits on the logo navy, not a palette colour', (tester) async {
    await tester.pumpWidget(host(const BrandMark()));

    final box = tester.widget<Container>(
      find.ancestor(of: find.byType(Image), matching: find.byType(Container)),
    );

    expect(
      (box.decoration as BoxDecoration).color,
      const Color(0xFF0C295A),
      reason: 'the ground is part of the artwork; a theme must not repaint it',
    );
  });

  testWidgets('a missing asset costs the mark, not the screen', (tester) async {
    await tester.pumpWidget(host(const BrandMark()));

    final image = tester.widget<Image>(find.byType(Image));

    expect(
      image.errorBuilder,
      isNotNull,
      reason: 'the welcome screen must still render if the asset is dropped',
    );
  });

  testWidgets('the tile is square at the size asked for', (tester) async {
    await tester.pumpWidget(host(const Center(child: BrandMark(size: 96))));

    expect(tester.getSize(find.byType(BrandMark)), const Size(96, 96));
  });
}
