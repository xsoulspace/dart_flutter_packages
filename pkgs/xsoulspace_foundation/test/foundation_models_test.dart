import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

void main() {
  group('LoadableContainer', () {
    test('loaded constructor marks value as loaded', () {
      final container = LoadableContainer<int>.loaded(42);

      expect(container.value, 42);
      expect(container.isLoaded, isTrue);
      expect(container.isLoading, isFalse);
    });
  });

  group('FieldContainer', () {
    test('defaults are deterministic', () {
      const field = FieldContainer<String>(value: 'input');

      expect(field.value, 'input');
      expect(field.errorText, isEmpty);
      expect(field.isLoading, isFalse);
    });
  });

  group('utility helpers', () {
    test('IdCreator generates UUID-like value', () {
      final id = IdCreator.create();

      expect(id, matches(RegExp(r'^[0-9a-fA-F-]{36}$')));
    });

    test('Randomizer.nextInt validates bounds and stays in range', () {
      final randomizer = Randomizer();

      expect(
        () => randomizer.nextInt(min: 5, max: 5),
        throwsArgumentError,
      );

      final value = randomizer.nextInt(min: 1, max: 3);
      expect(value, inInclusiveRange(1, 2));
    });

    test('String extension normalizes whitespace', () {
      final cleaned = 'a   b\n\t c'.clearWhitespaces();

      expect(cleaned, 'a b c');
      expect('https://example.com'.isUrl, isTrue);
      expect(''.getNullable(), isNull);
    });
  });
}
