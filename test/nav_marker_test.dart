import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/widgets/page_indicator.dart';

/// The marker points outward to the edge it is nearest, rather than
/// sitting as a flat block that looks the same wherever it lands.
void main() {
  const colour = Color(0xFFFF7A1A);

  List<Color> colours(int position, int count) =>
      (PageIndicator.markerFor(position, count, colour) as LinearGradient)
          .colors;

  test('the first holds its left and falls away to the right', () {
    final c = colours(0, 3);
    expect(c.first.a, 1.0);
    expect(c.last.a, lessThan(1.0));
  });

  test('the last holds its right and falls away to the left', () {
    final c = colours(2, 3);
    expect(c.first.a, lessThan(1.0));
    expect(c.last.a, 1.0);
  });

  test('anything in the middle falls away at both ends', () {
    final c = colours(1, 3);
    expect(c.first.a, lessThan(1.0));
    expect(c.last.a, lessThan(1.0));
    expect(c[1].a, 1.0, reason: 'solid through the middle');
  });

  test('it is the same colour throughout, only the alpha moves', () {
    for (final c in colours(1, 3)) {
      expect(c.r, colour.r);
      expect(c.g, colour.g);
      expect(c.b, colour.b);
    }
  });

  test('a single destination still gets a marker', () {
    expect(colours(0, 1), isNotEmpty);
  });
}
