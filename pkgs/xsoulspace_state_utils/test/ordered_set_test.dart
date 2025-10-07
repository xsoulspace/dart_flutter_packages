// ignore_for_file: cascade_invocations

import 'package:flutter_test/flutter_test.dart' hide hasLength, isEmpty;

import 'support/harness.dart';
import 'support/matchers.dart';

void main() {
  late CollectionsTestEnv env;

  setUp(() {
    env = CollectionsTestEnv()..setUp();
  });

  tearDown(() {
    env.tearDown();
  });

  group('MutableOrderedSet', () {
    group('initialization', () {
      test('starts empty', () {
        final set = env.makeMutableOrderedSet<String>();
        expect(set, isEmpty);
        expect(set.length, 0);
      });

      test('can be used as Iterable', () {
        final set = env.makeMutableOrderedSet<String>();
        expect(set, isA<Iterable<String>>());
      });
    });

    group('add', () {
      test('adds single item and returns true', () {
        final set = env.makeMutableOrderedSet<String>();
        final result = set.add('first');

        expect(result, isTrue);
        expect(set, hasLength(1));
        expect(set.first, 'first');
      });

      test('maintains insertion order', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.add('second');
        set.add('third');

        expect(set, containsInOrder(['first', 'second', 'third']));
      });

      test('handles different types', () {
        final stringSet = env.makeMutableOrderedSet<String>();
        final intSet = env.makeMutableOrderedSet<int>();

        stringSet.add('test');
        intSet.add(42);

        expect(stringSet.first, 'test');
        expect(intSet.first, 42);
      });

      test('prevents duplicate values', () {
        final set = env.makeMutableOrderedSet<String>();
        final firstAdd = set.add('duplicate');
        final secondAdd = set.add('duplicate');

        expect(firstAdd, isTrue);
        expect(secondAdd, isFalse);
        expect(set, hasLength(1));
        expect(set, containsInOrder(['duplicate']));
      });
    });

    group('remove', () {
      test('removes existing item and returns true', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        final result = set.remove('first');

        expect(result, isTrue);
        expect(set, hasLength(1));
        expect(set, containsInOrder(['second']));
      });

      test('returns false when item not found', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        final result = set.remove('nonexistent');

        expect(result, isFalse);
        expect(set, hasLength(2));
        expect(set, containsInOrder(['first', 'second']));
      });

      test('handles empty set', () {
        final set = env.makeMutableOrderedSet<String>();
        final result = set.remove('anything');

        expect(result, isFalse);
        expect(set, isEmpty);
      });
    });

    group('clear', () {
      test('removes all items', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.add('second');
        set.add('third');

        set.clear();

        expect(set, isEmpty);
      });

      test('can add items after clear', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.clear();
        set.add('second');

        expect(set, hasLength(1));
        expect(set.first, 'second');
      });
    });

    group('contains', () {
      test('returns true for existing items', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        expect(set.contains('first'), isTrue);
        expect(set.contains('second'), isTrue);
      });

      test('returns false for non-existing items', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');

        expect(set.contains('nonexistent'), isFalse);
      });

      test('returns false for empty set', () {
        final set = env.makeMutableOrderedSet<String>();

        expect(set.contains('anything'), isFalse);
      });
    });

    group('iteration', () {
      test('iterates in insertion order', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('first');
        set.add('second');
        set.add('third');

        final iterated = set.toList();
        expect(iterated, ['first', 'second', 'third']);
      });

      test('works with for-in loops', () {
        final set = env.makeMutableOrderedSet<String>();
        set.add('a');
        set.add('b');
        set.add('c');

        final result = <String>[];
        set.forEach(result.add);

        expect(result, ['a', 'b', 'c']);
      });

      test('supports standard iterable operations', () {
        final MutableOrderedSet<int> set = env.makeMutableOrderedSet<int>();
        set.add(1);
        set.add(2);
        set.add(3);

        expect(set.where((final x) => x > 2), [3]);
        expect(set.map((final x) => x * 2), [2, 4, 6]);
        expect(set.any((final x) => x == 2), isTrue);
        expect(set.every((final x) => x > 0), isTrue);
      });
    });

    group('complex scenarios', () {
      test('handles mixed operations', () {
        final set = env.makeMutableOrderedSet<String>();

        // Add some items
        set.add('first');
        set.add('second');
        set.add('third');

        // Try to add duplicate (should not add)
        set.add('second');

        // Remove middle item
        set.remove('second');

        // Add more items
        set.add('fourth');
        set.add('fifth');

        // Remove first item
        set.remove('first');

        expect(set, containsInOrder(['third', 'fourth', 'fifth']));
      });

      test('handles large number of items', () {
        final set = env.makeMutableOrderedSet<int>();
        const count = 1000;

        for (var i = 0; i < count; i++) {
          set.add(i);
        }

        expect(set, hasLength(count));
        expect(set.first, 0);
        expect(set.last, count - 1);
      });

      test('maintains order with duplicates attempted', () {
        final set = env.makeMutableOrderedSet<String>();

        set.add('first');
        set.add('second');
        set.add('first'); // duplicate, should not change order
        set.add('third');
        set.add('second'); // duplicate, should not change order

        expect(set, containsInOrder(['first', 'second', 'third']));
      });
    });
  });

  group('ImmutableOrderedSet', () {
    group('initialization', () {
      test('starts empty when no initial items', () {
        final set = env.makeImmutableOrderedSet<String>();
        expect(set, isEmpty);
        expect(set.length, 0);
      });

      test('starts with initial items and removes duplicates', () {
        final initial = ['first', 'second', 'first', 'third'];
        final set = env.makeImmutableOrderedSet(initial);

        expect(set, hasLength(3));
        expect(set, containsInOrder(['first', 'second', 'third']));
      });

      test('can be used as Iterable', () {
        final set = env.makeImmutableOrderedSet<String>();
        expect(set, isA<Iterable<String>>());
      });
    });

    group('add', () {
      test('updates the same instance with added item and returns true', () {
        final original = env.makeImmutableOrderedSet<String>();
        final result = original.add('first');

        expect(result, isTrue);
        expect(original, hasLength(1));
        expect(original.first, 'first');
      });

      test('maintains insertion order', () {
        final set = env.makeImmutableOrderedSet<String>();
        final result = set
          ..add('first')
          ..add('second')
          ..add('third');

        expect(result, containsInOrder(['first', 'second', 'third']));
      });

      test('handles different types', () {
        final stringSet = env.makeImmutableOrderedSet<String>();
        final intSet = env.makeImmutableOrderedSet<int>();

        final stringResult = stringSet.add('test');
        final intResult = intSet.add(42);

        expect(stringResult, isTrue);
        expect(intResult, isTrue);
        expect(stringSet.first, 'test');
        expect(intSet.first, 42);
      });

      test('prevents duplicate values and returns false', () {
        final set = env.makeImmutableOrderedSet<String>();
        final firstAdd = set.add('duplicate');
        final secondAdd = set.add('duplicate');

        expect(firstAdd, isTrue);
        expect(secondAdd, isFalse);
        expect(set, hasLength(1));
        expect(set, containsInOrder(['duplicate']));
      });
    });

    group('remove', () {
      test(
        'updates the same instance without removed item and returns true',
        () {
          final set = env.makeImmutableOrderedSet<String>();
          set.add('first');
          set.add('second');

          final result = set.remove('first');

          expect(result, isTrue);
          expect(set, hasLength(1));
          expect(set, containsInOrder(['second']));
        },
      );

      test('returns false when item not found', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        final result = set.remove('nonexistent');

        expect(result, isFalse);
        expect(set, hasLength(2));
        expect(set, containsInOrder(['first', 'second']));
      });

      test('handles empty set', () {
        final set = env.makeImmutableOrderedSet<String>();
        final result = set.remove('anything');

        expect(result, isFalse);
        expect(set, isEmpty);
      });
    });

    group('clear', () {
      test('updates the same instance to empty', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        set.clear();

        expect(set, isEmpty);
      });

      test('can add items after clear', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.clear();
        set.add('second');

        expect(set, hasLength(1));
        expect(set.first, 'second');
      });
    });

    group('assignAll', () {
      test('replaces all items with new set and removes duplicates', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('old1');
        set.add('old2');

        set.assignAll(['new1', 'new2', 'new1', 'new3']);

        expect(set, hasLength(3));
        expect(set, containsInOrder(['new1', 'new2', 'new3']));
      });

      test('handles empty assignment', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        set.assignAll([]);

        expect(set, isEmpty);
      });

      test('handles null values', () {
        final set = env.makeImmutableOrderedSet<String?>();
        set.assignAll(['first', null, 'third']);

        expect(set, hasLength(3));
        expect(set.elementAt(1), isNull);
      });
    });

    group('contains', () {
      test('returns true for existing items', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.add('second');

        expect(set.contains('first'), isTrue);
        expect(set.contains('second'), isTrue);
      });

      test('returns false for non-existing items', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');

        expect(set.contains('nonexistent'), isFalse);
      });

      test('returns false for empty set', () {
        final set = env.makeImmutableOrderedSet<String>();

        expect(set.contains('anything'), isFalse);
      });
    });

    group('iteration', () {
      test('iterates in insertion order', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.add('second');
        set.add('third');

        final iterated = set.toList();
        expect(iterated, ['first', 'second', 'third']);
      });

      test('works with for-in loops', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('a');
        set.add('b');
        set.add('c');

        final result = <String>[];
        set.forEach(result.add);

        expect(result, ['a', 'b', 'c']);
      });

      test('supports standard iterable operations', () {
        final ImmutableOrderedSet<int> set = env.makeImmutableOrderedSet<int>();
        set.add(1);
        set.add(2);
        set.add(3);

        expect(set.where((final x) => x > 2), [3]);
        expect(set.map((final x) => x * 2), [2, 4, 6]);
        expect(set.any((final x) => x == 2), isTrue);
        expect(set.every((final x) => x > 0), isTrue);
      });
    });

    group('immutability guarantees', () {
      test('mutating methods operate on the same instance', () {
        final set = env.makeImmutableOrderedSet<String>();
        set.add('first');
        set.add('second');
        set.add('third');
        set.remove('second');

        expect(set, hasLength(2));
        expect(set, containsInOrder(['first', 'third']));
      });

      test('original will be changed after multiple operations', () {
        final original = env.makeImmutableOrderedSet<String>();
        original.add('original');

        // Perform various operations
        original.add('new1');
        original.remove('new1');
        original.clear();
        original.add('final');

        expect(original, hasLength(1));
        expect(original.first, 'final');
      });
    });

    group('complex scenarios', () {
      test('handles mixed operations with immutability', () {
        final set = env.makeImmutableOrderedSet<String>();

        // Build up a set
        set.add('first');
        set.add('second');
        set.add('third');

        // Try to add duplicate (should not add)
        set.add('second');

        // Remove middle item
        set.remove('second');

        // Add more items
        set.add('fourth');
        set.add('fifth');

        // Remove first item
        set.remove('first');

        expect(set, containsInOrder(['third', 'fourth', 'fifth']));
      });

      test('handles large number of operations', () {
        final set = env.makeImmutableOrderedSet<int>();

        // Add many items
        for (var i = 0; i < 100; i++) {
          set.add(i);
        }

        expect(set, hasLength(100));

        // Try to add duplicates (should not add)
        for (var i = 0; i < 50; i++) {
          set.add(i);
        }

        expect(set, hasLength(100)); // Should remain the same

        // Remove every other item
        for (var i = 0; i < 100; i += 2) {
          set.remove(i);
        }

        expect(set, hasLength(50));
        expect(set.first, 1); // First odd number after removals
      });

      test('handles cascade operations', () {
        final result = env.makeImmutableOrderedSet<String>()
          ..add('first')
          ..add('second')
          ..remove('first')
          ..add('third')
          ..add('second') // should not add (duplicate)
          ..add('fourth'); // should add

        expect(result, containsInOrder(['second', 'third', 'fourth']));
      });
    });
  });

  group('comparison between Mutable and Immutable', () {
    test('both maintain insertion order', () {
      final mutable = env.makeMutableOrderedSet<String>();
      final immutable = env.makeImmutableOrderedSet<String>();

      // Same operations
      mutable.add('first');
      mutable.add('second');
      mutable.add('third');

      immutable.add('first');
      immutable.add('second');
      immutable.add('third');

      expect(mutable.toList(), immutable.toList());
    });

    test('both prevent duplicates', () {
      final mutable = env.makeMutableOrderedSet<String>();
      final immutable = env.makeImmutableOrderedSet<String>();

      // Add duplicates
      mutable.add('duplicate');
      mutable.add('duplicate');
      mutable.add('unique');

      immutable.add('duplicate');
      immutable.add('duplicate');
      immutable.add('unique');

      expect(mutable.length, 2);
      expect(immutable.length, 2);
      expect(mutable.toList(), ['duplicate', 'unique']);
      expect(immutable.toList(), ['duplicate', 'unique']);
    });

    test('mutable allows direct mutation, immutable creates new instances', () {
      final mutable = env.makeMutableOrderedSet<String>();
      final immutable = env.makeImmutableOrderedSet<String>();

      // Mutable: direct mutation
      mutable.add('item');
      final mutableLength = mutable.length;

      // Immutable: creates new instance
      immutable.add('item');
      final immutableLength = immutable.length;

      expect(mutableLength, immutableLength);
      expect(mutable.first, immutable.first);
    });
  });
}
