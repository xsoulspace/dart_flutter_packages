import 'package:test/test.dart';
import 'package:universal_lexicon/universal_lexicon.dart';

void main() {
  test('log scale keeps orders of magnitude comparable', () {
    final normalized = normalizeCounts(const {
      'the': 1000000,
      'house': 10000,
      'marble': 100,
      'obsidian': 1,
    });
    expect(normalized['the'], 1.0);
    expect(normalized['obsidian'], 0.05);
    // A 100× raw gap is ONE decade in log space: equal log gaps rank
    // equally far apart.
    final theHouse = 1.0 - normalized['house']!;
    final houseMarble = normalized['house']! - normalized['marble']!;
    expect(theHouse, closeTo(houseMarble, 1e-9));
  });

  test('single word and equal counts map to 1.0', () {
    expect(normalizeCounts(const {'only': 5}), {'only': 1.0});
    expect(normalizeCounts(const {'a': 10, 'b': 10}).values, everyElement(1.0));
  });

  test('empty input, custom floor, unattested count 0', () {
    expect(normalizeCounts(const {}), isEmpty);
    final floored = normalizeCounts(
      const {'a': 100, 'b': 1},
      floor: 0.5,
    );
    expect(floored['b'], 0.5);
    expect(normalizeCounts(const {'a': 0})['a'], 1.0);
  });
}
