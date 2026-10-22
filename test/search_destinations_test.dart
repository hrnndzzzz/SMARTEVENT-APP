import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/search_destinations.dart';

/// Searching for help should land you somewhere.
///
/// The box knew only about events and expenses, so "reports" — a word
/// for a screen rather than a record — found nothing at all.
void main() {
  SearchDestination only(String query) {
    final found = SearchDestination.matching(query);
    expect(found, isNotEmpty, reason: '"$query" found nothing');
    return found.first;
  }

  test('a word for a screen finds the screen', () {
    expect(only('reports').title, 'Financial reports');
    expect(only('inventory').title, 'Inventory');
    expect(only('settings').title, 'Settings');
  });

  test('and a word nobody put on it does too', () {
    // None of these appear in the screens' own names.
    expect(only('csv').title, 'Financial reports');
    expect(only('receipt').title, 'Record an expense');
    expect(only('duplicate').title, 'Flagged for review');
    expect(only('dark').title, 'Settings');
  });

  test('singular and plural both land', () {
    expect(only('report').title, only('reports').title);
    expect(only('category').title, only('categories').title);
  });

  test('a half-typed word still lands', () {
    expect(only('rep').title, 'Financial reports');
    expect(only('inv').title, 'Inventory');
  });

  test('asking for help finds help', () {
    expect(
      SearchDestination.matching('help').map((d) => d.title),
      contains('Help and support'),
    );
  });

  test('nothing typed finds nothing', () {
    expect(SearchDestination.matching(''), isEmpty);
    expect(SearchDestination.matching('   '), isEmpty);
  });

  test('a word that means nothing here finds nothing', () {
    expect(SearchDestination.matching('zzzzz'), isEmpty);
  });

  test('every destination is reachable by its own name', () {
    for (final place in SearchDestination.all) {
      expect(
        SearchDestination.matching(place.title).map((d) => d.title),
        contains(place.title),
        reason: place.title,
      );
    }
  });

  test('and none of them share a name', () {
    expect(
      {for (final d in SearchDestination.all) d.title},
      hasLength(SearchDestination.all.length),
    );
  });
}
