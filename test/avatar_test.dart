import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/avatar.dart';

/// The picture is generated from the name, so the same person keeps the
/// same mark across devices and sessions without anything being stored.
void main() {
  test('initials never come back empty', () {
    expect(Avatar.initialsFor('Demo Admin'), 'DA');
    expect(Avatar.initialsFor('Prince'), 'P');
    expect(Avatar.initialsFor('  jasper   hernandez '), 'JH');
    expect(Avatar.initialsFor(''), '?');
    expect(Avatar.initialsFor('   '), '?');
  });

  test('a name always picks the same colour and pattern', () {
    final a = Avatar();
    final b = Avatar();
    expect(a.colorFor('Demo Admin'), b.colorFor('Demo Admin'));
    expect(a.patternFor('Demo Admin'), b.patternFor('Demo Admin'));
  });

  test('the seed ignores case and surrounding space', () {
    expect(avatarSeed('Demo Admin'), avatarSeed('  demo admin  '));
  });

  test('different names generally differ', () {
    final names = [
      'Demo Admin',
      'Demo Treasurer',
      'Jasper Hernandez',
      'Sionel Caramel',
      'Daniela Mayormita',
    ];
    final avatar = Avatar();
    final marks = {
      for (final n in names) '${avatar.colorFor(n)}/${avatar.patternFor(n)}',
    };
    // Eight colours by eight patterns is sixty-four combinations, so
    // five names colliding would mean the seed is not spreading.
    expect(marks.length, greaterThan(3));
  });

  test('every generated colour is one of the eight', () {
    final avatar = Avatar();
    for (final n in ['a', 'bb', 'Demo Admin', 'Zzz Yyy']) {
      expect(avatarColors, contains(avatar.colorFor(n)));
    }
  });
}
