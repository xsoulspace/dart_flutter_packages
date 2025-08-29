// ignore_for_file: cascade_invocations

import 'package:test/test.dart' hide hasLength, isEmpty;

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

  group('MutableOrderedList', () {
    group('initialization', () {
      test('starts empty', () {
        final list = env.makeMutableOrderedList<String>();
        expect(list, isEmpty);
        expect(list.length, 0);
      });

      test('can be used as Iterable', () {
        final list = env.makeMutableOrderedList<String>();
        expect(list, isA<Iterable<String>>());
      });
    });

    group('add', () {
      test('adds single item', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');

        expect(list, hasLength(1));
        expect(list.first, 'first');
      });

      test('maintains insertion order', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('third');

        expect(list, containsInOrder(['first', 'second', 'third']));
      });

      test('handles different types', () {
        final stringList = env.makeMutableOrderedList<String>();
        final intList = env.makeMutableOrderedList<int>();

        stringList.add('test');
        intList.add(42);

        expect(stringList.first, 'test');
        expect(intList.first, 42);
      });

      test('allows duplicate values', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('duplicate');
        list.add('duplicate');

        expect(list, hasLength(2));
        expect(list, containsInOrder(['duplicate', 'duplicate']));
      });
    });

    group('remove', () {
      test('removes first occurrence', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('first');

        list.remove('first');

        expect(list, hasLength(2));
        expect(list, containsInOrder(['second', 'first']));
      });

      test('does nothing when item not found', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');
        list.add('second');

        list.remove('nonexistent');

        expect(list, hasLength(2));
        expect(list, containsInOrder(['first', 'second']));
      });

      test('handles empty list', () {
        final list = env.makeMutableOrderedList<String>();
        list.remove('anything');

        expect(list, isEmpty);
      });
    });

    group('clear', () {
      test('removes all items', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('third');

        list.clear();

        expect(list, isEmpty);
      });

      test('can add items after clear', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');
        list.clear();
        list.add('second');

        expect(list, hasLength(1));
        expect(list.first, 'second');
      });
    });

    group('iteration', () {
      test('iterates in insertion order', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('third');

        final iterated = list.toList();
        expect(iterated, ['first', 'second', 'third']);
      });

      test('works with for-in loops', () {
        final list = env.makeMutableOrderedList<String>();
        list.add('a');
        list.add('b');
        list.add('c');

        final result = <String>[];
        list.forEach(result.add);

        expect(result, ['a', 'b', 'c']);
      });

      test('supports standard iterable operations', () {
        final list = env.makeMutableOrderedList<int>();
        list.add(1);
        list.add(2);
        list.add(3);

        expect(list.where((final x) => x > 2), [3]);
        expect(list.map((final x) => x * 2), [2, 4, 6]);
        expect(list.any((final x) => x == 2), isTrue);
        expect(list.every((final x) => x > 0), isTrue);
      });
    });

    group('complex scenarios', () {
      test('handles mixed operations', () {
        final list = env.makeMutableOrderedList<String>();

        // Add some items
        list.add('first');
        list.add('second');
        list.add('third');

        // Remove middle item
        list.remove('second');

        // Add more items
        list.add('fourth');
        list.add('fifth');

        // Remove first item
        list.remove('first');

        expect(list, containsInOrder(['third', 'fourth', 'fifth']));
      });

      test('handles large number of items', () {
        final list = env.makeMutableOrderedList<int>();
        const count = 1000;

        for (var i = 0; i < count; i++) {
          list.add(i);
        }

        expect(list, hasLength(count));
        expect(list.first, 0);
        expect(list.last, count - 1);
      });
    });
  });

  group('ImmutableOrderedList', () {
    group('initialization', () {
      test('starts empty when no initial items', () {
        final list = env.makeImmutableOrderedList<String>();
        expect(list, isEmpty);
        expect(list.length, 0);
      });

      test('starts with initial items', () {
        final initial = ['first', 'second', 'third'];
        final list = env.makeImmutableOrderedList(initial);

        expect(list, hasLength(3));
        expect(list, containsInOrder(initial));
      });

      test('can be used as Iterable', () {
        final list = env.makeImmutableOrderedList<String>();
        expect(list, isA<Iterable<String>>());
      });
    });

    group('add', () {
      test('updates the same instance with added item', () {
        final original = env.makeImmutableOrderedList<String>();
        final result = original..add('first');

        expect(original, hasLength(1));
        expect(result, hasLength(1));
        expect(result.first, 'first');
      });

      test('maintains insertion order', () {
        final list = env.makeImmutableOrderedList<String>();
        final result = list
          ..add('first')
          ..add('second')
          ..add('third');

        expect(result, containsInOrder(['first', 'second', 'third']));
      });

      test('handles different types', () {
        final stringList = env.makeImmutableOrderedList<String>();
        final intList = env.makeImmutableOrderedList<int>();

        final stringResult = stringList..add('test');
        final intResult = intList..add(42);

        expect(stringResult.first, 'test');
        expect(intResult.first, 42);
      });

      test('allows duplicate values', () {
        final list = env.makeImmutableOrderedList<String>();
        final result = list
          ..add('duplicate')
          ..add('duplicate');

        expect(result, hasLength(2));
        expect(result, containsInOrder(['duplicate', 'duplicate']));
      });
    });

    group('addUnique', () {
      test('adds unique item and returns true', () {
        final list = env.makeImmutableOrderedList<String>();
        final result = list.addUnique('first');

        expect(result, isTrue);
        expect(list, hasLength(1));
        expect(list.first, 'first');
      });

      test('does not add duplicate and returns false', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        final result = list.addUnique('first');

        expect(result, isFalse);
        expect(list, hasLength(1));
      });

      test('maintains order with mixed unique and duplicate adds', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.addUnique('second'); // should add
        list.addUnique('first'); // should not add
        list.add('third');

        expect(list, containsInOrder(['first', 'second', 'third']));
      });
    });

    group('remove', () {
      test('updates the same instance without removed item', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');

        final originalLength = list.length;
        list.remove('first');

        expect(list, hasLength(originalLength - 1));
        expect(list, containsInOrder(['second']));
      });

      test('removes first occurrence only', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('first');

        list.remove('first');

        expect(list, hasLength(2));
        expect(list, containsInOrder(['second', 'first']));
      });

      test('does nothing when item not found', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');

        list.remove('nonexistent');

        expect(list, hasLength(2));
        expect(list, containsInOrder(['first', 'second']));
      });

      test('handles empty list', () {
        final list = env.makeImmutableOrderedList<String>();
        list.remove('anything');

        expect(list, isEmpty);
      });
    });

    group('clear', () {
      test('updates the same instance to empty', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');

        list.clear();

        expect(list, isEmpty);
      });

      test('can add items after clear', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.clear();
        list.add('second');

        expect(list, hasLength(1));
        expect(list.first, 'second');
      });
    });

    group('assignAll', () {
      test('replaces all items with new list', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('old1');
        list.add('old2');

        list.assignAll(['new1', 'new2', 'new3']);

        expect(list, hasLength(3));
        expect(list, containsInOrder(['new1', 'new2', 'new3']));
      });

      test('handles empty assignment', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');

        list.assignAll([]);

        expect(list, isEmpty);
      });

      test('handles null values', () {
        final list = env.makeImmutableOrderedList<String?>();
        list.assignAll(['first', null, 'third']);

        expect(list, hasLength(3));
        expect(list.elementAt(1), isNull);
      });
    });

    group('iteration', () {
      test('iterates in insertion order', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('third');

        final iterated = list.toList();
        expect(iterated, ['first', 'second', 'third']);
      });

      test('works with for-in loops', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('a');
        list.add('b');
        list.add('c');

        final result = <String>[];
        list.forEach(result.add);

        expect(result, ['a', 'b', 'c']);
      });

      test('supports standard iterable operations', () {
        final list = env.makeImmutableOrderedList<int>();
        list.add(1);
        list.add(2);
        list.add(3);

        expect(list.where((final x) => x > 2), [3]);
        expect(list.map((final x) => x * 2), [2, 4, 6]);
        expect(list.any((final x) => x == 2), isTrue);
        expect(list.every((final x) => x > 0), isTrue);
      });
    });

    group('immutability guarantees', () {
      test('mutating methods operate on the same instance', () {
        final list = env.makeImmutableOrderedList<String>();
        list.add('first');
        list.add('second');
        list.add('third');
        list.remove('second');

        expect(list, hasLength(2));
        expect(list, containsInOrder(['first', 'third']));
      });

      test('original will be changed after multiple operations', () {
        final original = env.makeImmutableOrderedList<String>();
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
        final list = env.makeImmutableOrderedList<String>();

        // Build up a list
        list.add('first');
        list.add('second');
        list.add('third');

        // Remove middle item
        list.remove('second');

        // Add more items
        list.add('fourth');
        list.add('fifth');

        // Remove first item
        list.remove('first');

        expect(list, containsInOrder(['third', 'fourth', 'fifth']));
      });

      test('handles large number of operations', () {
        final list = env.makeImmutableOrderedList<int>();

        // Add many items
        for (var i = 0; i < 100; i++) {
          list.add(i);
        }

        expect(list, hasLength(100));

        // Remove every other item
        for (var i = 0; i < 100; i += 2) {
          list.remove(i);
        }

        expect(list, hasLength(50));
        expect(list.first, 1); // First even number after removals
      });

      test('handles cascade operations', () {
        final result = env.makeImmutableOrderedList<String>()
          ..add('first')
          ..add('second')
          ..remove('first')
          ..add('third')
          ..addUnique('second') // should not add
          ..addUnique('fourth'); // should add

        expect(result, containsInOrder(['second', 'third', 'fourth']));
      });
    });
  });

  group('comparison between Mutable and Immutable', () {
    test('both maintain insertion order', () {
      final mutable = env.makeMutableOrderedList<String>();
      final immutable = env.makeImmutableOrderedList<String>();

      // Same operations
      mutable.add('first');
      mutable.add('second');
      mutable.add('third');

      immutable.add('first');
      immutable.add('second');
      immutable.add('third');

      expect(mutable.toList(), immutable.toList());
    });

    test('mutable allows direct mutation, immutable creates new instances', () {
      final mutable = env.makeMutableOrderedList<String>();
      final immutable = env.makeImmutableOrderedList<String>();

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
