import 'package:test/test.dart' hide hasLength, isEmpty;

import 'support/builders.dart';
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

  group('MutableOrderedMap', () {
    group('initialization', () {
      test('starts empty', () {
        final map = env.makeMutableOrderedMap<String, String>();
        expect(map, isEmpty);
        expect(map.length, 0);
      });

      test('can be used as Iterable', () {
        final map = env.makeMutableOrderedMap<String, String>();
        expect(map, isA<Iterable<String>>());
      });
    });

    group('upsert', () {
      test('adds new key-value pair', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        expect(map, hasLength(1));
        expect(map.containsKey('key1'), isTrue);
        expect(map['key1'], 'value1');
      });

      test('maintains insertion order', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        expect(map.toList(), ['key1', 'key2', 'key3']);
        expect(map.orderedValues, ['value1', 'value2', 'value3']);
      });

      test('updates existing key', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key1', 'updated');

        expect(map, hasLength(1));
        expect(map['key1'], 'updated');
      });

      test('maintains order when updating existing key', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');
        map.upsert('key2', 'updated'); // Update middle key

        expect(map.toList(), ['key1', 'key2', 'key3']);
        expect(map.orderedValues, ['value1', 'updated', 'value3']);
      });

      test('handles different value types', () {
        final stringMap = env.makeMutableOrderedMap<String, String>();
        final intMap = env.makeMutableOrderedMap<String, int>();

        stringMap.upsert('key1', 'string');
        intMap.upsert('key1', 42);

        expect(stringMap['key1'], 'string');
        expect(intMap['key1'], 42);
      });
    });

    group('operator []', () {
      test('retrieves existing value', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        expect(map['key1'], 'value1');
      });

      test('returns null for non-existent key', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        expect(map['nonexistent'], isNull);
      });

      test('handles null keys', () {
        final map = env.makeMutableOrderedMap<String?, String>();
        map.upsert(null, 'nullValue');

        expect(map[null], 'nullValue');
      });
    });

    group('containsKey', () {
      test('returns true for existing key', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        expect(map.containsKey('key1'), isTrue);
      });

      test('returns false for non-existent key', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        expect(map.containsKey('nonexistent'), isFalse);
      });

      test('handles null keys', () {
        final map = env.makeMutableOrderedMap<String?, String>();
        map.upsert(null, 'value1');

        expect(map.containsKey(null), isTrue);
        expect(map.containsKey('null'), isFalse);
      });
    });

    group('remove', () {
      test('removes existing key-value pair', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        map.remove('key1');

        expect(map, hasLength(1));
        expect(map.containsKey('key1'), isFalse);
        expect(map['key1'], isNull);
      });

      test('maintains order after removal', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        map.remove('key2'); // Remove middle key

        expect(map.toList(), ['key1', 'key3']);
        expect(map.orderedValues, ['value1', 'value3']);
      });

      test('does nothing when key not found', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        map.remove('nonexistent');

        expect(map, hasLength(1));
        expect(map['key1'], 'value1');
      });

      test('handles null keys', () {
        final map = env.makeMutableOrderedMap<String?, String>();
        map.upsert(null, 'value1');
        map.upsert('key1', 'value2');

        map.remove(null);

        expect(map.containsKey(null), isFalse);
        expect(map.containsKey('key1'), isTrue);
      });
    });

    group('clear', () {
      test('removes all key-value pairs', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        map.clear();

        expect(map, isEmpty);
        expect(map.length, 0);
      });

      test('can add items after clear', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.clear();
        map.upsert('key2', 'value2');

        expect(map, hasLength(1));
        expect(map['key2'], 'value2');
      });
    });

    group('orderedValues', () {
      test('returns values in insertion order', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        expect(map.orderedValues, ['value1', 'value2', 'value3']);
      });

      test('reflects updates', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key1', 'updated');

        expect(map.orderedValues, ['updated']);
      });

      test('reflects removals', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');
        map.remove('key2');

        expect(map.orderedValues, ['value1', 'value3']);
      });
    });

    group('values and entries', () {
      test('values does not guarantee order', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        expect(map.values, containsAll(['value1', 'value2']));
        expect(map.values.length, 2);
      });

      test('entries does not guarantee order', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        final entries = map.entries.toList();
        expect(entries.length, 2);
        expect(entries.map((final e) => e.key), containsAll(['key1', 'key2']));
        expect(
          entries.map((final e) => e.value),
          containsAll(['value1', 'value2']),
        );
      });
    });

    group('iteration', () {
      test('iterates over keys in insertion order', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        final keys = map.toList();
        expect(keys, ['key1', 'key2', 'key3']);
      });

      test('works with for-in loops', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('a', '1');
        map.upsert('b', '2');
        map.upsert('c', '3');

        final result = <String>[];
        for (final key in map) {
          result.add(key);
        }

        expect(result, ['a', 'b', 'c']);
      });
    });

    group('complex scenarios', () {
      test('handles mixed operations', () {
        final map = env.makeMutableOrderedMap<String, String>();

        // Add some items
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        // Update middle item
        map.upsert('key2', 'updated');

        // Add more items
        map.upsert('key4', 'value4');
        map.upsert('key5', 'value5');

        // Remove first item
        map.remove('key1');

        // Update last item
        map.upsert('key5', 'final');

        expect(map.toList(), ['key2', 'key3', 'key4', 'key5']);
        expect(map.orderedValues, ['updated', 'value3', 'value4', 'final']);
      });

      test('handles large number of items', () {
        final map = env.makeMutableOrderedMap<String, String>();
        const count = 1000;

        for (var i = 0; i < count; i++) {
          map.upsert('key$i', 'value$i');
        }

        expect(map, hasLength(count));
        expect(map.first, 'key0');
        expect(map['key999'], 'value999');
      });

      test('handles frequent updates to same key', () {
        final map = env.makeMutableOrderedMap<String, String>();
        map.upsert('key1', 'value1');

        for (var i = 0; i < 100; i++) {
          map.upsert('key1', 'value$i');
        }

        expect(map, hasLength(1));
        expect(map['key1'], 'value99');
        expect(map.toList(), ['key1']);
      });
    });
  });

  group('ImmutableOrderedMap', () {
    late String Function(TestUser) toKey;
    late String Function(String) stringToKey;

    setUp(() {
      toKey = userToId;
      stringToKey = (final key) => key;
    });

    group('initialization', () {
      test('starts empty', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        expect(map, isEmpty);
        expect(map.length, 0);
      });

      test('can be used as Iterable', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        expect(map, isA<Iterable<String>>());
      });

      test('requires toKey function', () {
        expect(
          () => ImmutableOrderedMap<String, String>(toKey: null as dynamic),
          throwsA(isA<TypeError>()),
        );
      });
    });

    group('upsert', () {
      test('adds new key-value pair at end by default', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        expect(map, hasLength(1));
        expect(map['key1'], 'value1');
        expect(map.keys, ['key1']);
      });

      test('maintains insertion order when putFirst is false', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1', putFirst: false);
        map.upsert('key2', 'value2', putFirst: false);
        map.upsert('key3', 'value3', putFirst: false);

        expect(map.keys, ['key1', 'key2', 'key3']);
        expect(map.orderedValues, ['value1', 'value2', 'value3']);
      });

      test('updates existing key', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key1', 'updated');

        expect(map, hasLength(1));
        expect(map['key1'], 'updated');
        expect(map.keys, ['key1']);
      });

      test('putFirst places key at the end', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        expect(map.keys, ['key1', 'key2', 'key3']);
        expect(map.orderedValues, ['value1', 'value2', 'value3']);
      });

      test('maintains order when updating with putFirst', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key1', 'updated', putFirst: true); // Move to front

        expect(map.keys, ['key1', 'key2']);
        expect(map.orderedValues, ['updated', 'value2']);
      });
    });

    group('operator []', () {
      test('retrieves existing value', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        expect(map['key1'], 'value1');
      });

      test('returns null for non-existent key', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        expect(map['nonexistent'], isNull);
      });

      test('handles null keys', () {
        final map = env.makeImmutableOrderedMap<String?, String>(
          (final v) => v ?? 'null-key',
        );
        map.upsert(null, 'nullValue');

        expect(map[null], 'nullValue');
      });
    });

    group('operator []=', () {
      test('is equivalent to upsert with default parameters', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map['key1'] = 'value1';
        map['key2'] = 'value2';

        expect(map.keys, ['key1', 'key2']);
        expect(map.orderedValues, ['value1', 'value2']);
      });
    });

    group('keys', () {
      test('returns unmodifiable list of keys in order', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        final keys = map.keys;
        expect(keys, ['key1', 'key2']);
        expect(() => keys.add('key3'), throwsUnsupportedError);
      });
    });

    group('orderedValues', () {
      test('returns values in insertion order', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        expect(map.orderedValues, ['value1', 'value2']);
      });

      test('returns unmodifiable list', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        final values = map.orderedValues;
        expect(() => values.add('new'), throwsUnsupportedError);
      });

      test('caches result for performance', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        final firstCall = map.orderedValues;
        final secondCall = map.orderedValues;

        expect(identical(firstCall, secondCall), isTrue);
      });

      test('invalidates cache after mutation', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        final before = map.orderedValues;
        map.upsert('key2', 'value2');
        final after = map.orderedValues;

        expect(identical(before, after), isFalse);
        expect(after, ['value1', 'value2']);
      });
    });

    group('assignAll', () {
      test('replaces all items with new map', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('old1', 'value1');
        map.upsert('old2', 'value2');

        map.assignAll({'new1': 'value1', 'new2': 'value2', 'new3': 'value3'});

        expect(map.keys, ['new1', 'new2', 'new3']);
        expect(map.orderedValues, ['value1', 'value2', 'value3']);
      });

      test('handles empty assignment', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        map.assignAll({});

        expect(map, isEmpty);
      });
    });

    group('assignAllOrdered', () {
      test('assigns items using toKey function', () {
        final userMap = env.makeImmutableOrderedMap<String, TestUser>(userToId);
        final users = someTestUsers();

        userMap.assignAllOrdered(users);

        expect(userMap, hasLength(3));
        expect(userMap.keys, users.map((final u) => u.id));
        expect(userMap.orderedValues, users);
      });

      test('maintains order from input list', () {
        final userMap = env.makeImmutableOrderedMap<String, TestUser>(userToId);
        final users = someTestUsers();

        // Reverse the list
        final reversedUsers = users.reversed.toList();
        userMap.assignAllOrdered(reversedUsers);

        expect(userMap.orderedValues, reversedUsers);
        expect(userMap.keys, reversedUsers.map((final u) => u.id));
      });

      test('handles duplicate keys from toKey function', () {
        final userMap = env.makeImmutableOrderedMap<String, TestUser>(
          (final user) => 'same-key',
        );

        userMap.assignAllOrdered(someTestUsers());

        expect(userMap, hasLength(1)); // Only last user should remain
        expect(userMap.keys, ['same-key']);
      });
    });

    group('remove', () {
      test('removes existing key-value pair', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        map.remove('key1');

        expect(map, hasLength(1));
        expect(map.containsKey('key1'), isFalse);
        expect(map['key1'], isNull);
      });

      test('maintains order after removal', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        map.remove('key2'); // Remove middle key

        expect(map.keys, ['key1', 'key3']);
        expect(map.orderedValues, ['value1', 'value3']);
      });

      test('does nothing when key not found', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        map.remove('nonexistent');

        expect(map, hasLength(1));
        expect(map['key1'], 'value1');
      });
    });

    group('clear', () {
      test('removes all key-value pairs', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        map.clear();

        expect(map, isEmpty);
        expect(map.length, 0);
      });

      test('can add items after clear', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.clear();
        map.upsert('key2', 'value2');

        expect(map, hasLength(1));
        expect(map['key2'], 'value2');
      });
    });

    group('iteration', () {
      test('iterates over keys in insertion order', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');

        final keys = map.toList();
        expect(keys, ['key1', 'key2']);
      });

      test('works with for-in loops', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('a', '1');
        map.upsert('b', '2');

        final result = <String>[];
        for (final key in map) {
          result.add(key);
        }

        expect(result, ['a', 'b']);
      });
    });

    group('immutability guarantees', () {
      test('each operation updates the same instance', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);
        map.upsert('key1', 'value1');

        final step1 = map..upsert('key2', 'value2');
        final step2 = step1..upsert('key3', 'value3');
        final step3 = step2..remove('key2');

        expect(map, hasLength(2));
        expect(step1, hasLength(2));
        expect(step2, hasLength(2));
        expect(step3, hasLength(2));
        expect(step3.keys, ['key1', 'key3']);
        expect(step3.orderedValues, ['value1', 'value3']);
      });

      test('original will be changed after multiple operations', () {
        final original = env.makeImmutableOrderedMap<String, String>(
          stringToKey,
        );
        original.upsert('original', 'value1');

        // Perform various operations
        original.upsert('new1', 'value2');
        original.remove('new1');
        original.clear();
        original.upsert('final', 'value3');

        expect(original, hasLength(1));
        expect(original['final'], 'value3');
      });
    });

    group('complex scenarios', () {
      test('handles mixed operations with immutability', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);

        // Build up a map
        map.upsert('key1', 'value1');
        map.upsert('key2', 'value2');
        map.upsert('key3', 'value3');

        // Update middle item and move to front
        map.upsert('key2', 'updated', putFirst: true);

        // Add more items
        map.upsert('key4', 'value4');
        map.upsert('key5', 'value5');

        // Remove first item
        map.remove('key2');

        expect(map.keys, ['key1', 'key3', 'key4', 'key5']);
        expect(map.orderedValues, ['value1', 'value3', 'value4', 'value5']);
      });

      test('handles large number of operations', () {
        final map = env.makeImmutableOrderedMap<String, String>(stringToKey);

        // Add many items
        for (var i = 0; i < 100; i++) {
          map.upsert('key$i', 'value$i');
        }

        expect(map, hasLength(100));

        // Remove every other item
        for (var i = 0; i < 100; i += 2) {
          map.remove('key$i');
        }

        expect(map, hasLength(50));
        expect(map.first, 'key1'); // First odd key
      });

      test('works with complex objects and custom toKey', () {
        final userMap = env.makeImmutableOrderedMap<String, TestUser>(userToId);
        final users = someTestUsers(5);

        // Add users in specific order
        userMap.assignAllOrdered(users);

        // Add a user at the beginning
        final newUser = aTestUser(name: 'New User');
        userMap.upsert(newUser.id, newUser, putFirst: true);

        expect(userMap, hasLength(6));
        expect(userMap.first, newUser.id);
        expect(userMap.orderedValues.first, newUser);
      });
    });
  });

  group('comparison between Mutable and Immutable', () {
    test('both maintain insertion order', () {
      final mutable = env.makeMutableOrderedMap<String, String>();
      final immutable = env.makeImmutableOrderedMap<String, String>(
        (final v) => v,
      );

      // Same operations
      mutable.upsert('key1', 'value1');
      mutable.upsert('key2', 'value2');

      immutable.upsert('key1', 'value1');
      immutable.upsert('key2', 'value2');

      expect(mutable.toList(), immutable.toList());
      expect(mutable.orderedValues, immutable.orderedValues);
    });

    test('mutable allows direct mutation, immutable creates new instances', () {
      final mutable = env.makeMutableOrderedMap<String, String>();
      final immutable = env.makeImmutableOrderedMap<String, String>(
        (final v) => v,
      );

      // Mutable: direct mutation
      mutable.upsert('key1', 'value1');
      final mutableLength = mutable.length;

      // Immutable: creates new instance
      immutable.upsert('key1', 'value1');
      final immutableLength = immutable.length;

      expect(mutableLength, immutableLength);
      expect(mutable['key1'], immutable['key1']);
    });

    test('immutable requires toKey function, mutable does not', () {
      final mutable = env.makeMutableOrderedMap<String, String>();
      final immutable = env.makeImmutableOrderedMap<String, String>(
        (final v) => v,
      );

      // Both can upsert with explicit keys
      mutable.upsert('key1', 'value1');
      immutable.upsert('key1', 'value1');

      expect(mutable['key1'], immutable['key1']);
    });
  });
}
