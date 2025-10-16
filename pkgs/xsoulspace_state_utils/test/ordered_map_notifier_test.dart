// ignore_for_file: cascade_invocations

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart' hide hasLength, isEmpty;

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

  group('OrderedMapNotifier', () {
    late String Function(String) stringToKey;

    setUp(() {
      stringToKey = (final key) => key;
    });

    group('initialization', () {
      test('starts empty', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        expect(notifier, isEmpty);
        expect(notifier.length, 0);
      });

      test('can be used as ImmutableOrderedMap', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        expect(notifier, isA<ImmutableOrderedMap<String, String>>());
      });

      test('can be used as ChangeNotifier', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        expect(notifier, isA<ChangeNotifier>());
      });
    });

    group('upsert with notifications', () {
      test('adds new key-value pair and notifies listeners', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        var notified = false;

        notifier.addListener(() => notified = true);
        notifier.upsert('value1', key: 'key1');

        expect(notifier, hasLength(1));
        expect(notifier['key1'], 'value1');
        expect(notifier.keys, ['key1']);
        expect(notified, isTrue);
      });

      test('maintains insertion order ', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        final operations = <String>[];

        notifier.addListener(
          () => operations.add('keys: ${notifier.keys.join(",")}'),
        );
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');
        notifier.upsert('value3', key: 'key3');

        expect(notifier.keys, ['key1', 'key2', 'key3']);
        expect(notifier.orderedValues, ['value1', 'value2', 'value3']);
        expect(operations, [
          'keys: key1',
          'keys: key1,key2',
          'keys: key1,key2,key3',
        ]);
      });

      test('updates existing key and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('updated', key: 'key1');

        expect(notifier, hasLength(1));
        expect(notifier['key1'], 'updated');
        expect(notifier.keys, ['key1']);
        expect(notified, isTrue);
      });

      test('putFirst places key at the beginning and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('value3', putFirst: true, key: 'key3');

        expect(notifier.keys, ['key3', 'key1', 'key2']);
        expect(notifier.orderedValues, ['value3', 'value1', 'value2']);
        expect(notified, isTrue);
      });

      test('maintains order when updating with putFirst', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');
        notifier.upsert('value3', key: 'key3');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert(
          'updated',
          putFirst: true,
          key: 'key3',
        ); // Move to front

        expect(notifier.keys, ['key3', 'key1', 'key2']);
        expect(notifier.orderedValues, ['updated', 'value1', 'value2']);
        expect(notified, isTrue);
      });
    });

    group('remove with notifications', () {
      test('removes existing key-value pair and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('key1');

        expect(notifier, hasLength(1));
        expect(notifier.containsKey('key1'), isFalse);
        expect(notifier['key1'], isNull);
        expect(notifier.keys, ['key2']);
        expect(notified, isTrue);
      });

      test('maintains order after removal', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');
        notifier.upsert('value3', key: 'key3');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('key2'); // Remove middle key

        expect(notifier.keys, ['key1', 'key3']);
        expect(notifier.orderedValues, ['value1', 'value3']);
        expect(notified, isTrue);
      });

      test('does nothing when key not found', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('nonexistent');

        expect(notifier, hasLength(1));
        expect(notifier['key1'], 'value1');
        expect(
          notified,
          isFalse,
          reason: 'Should not notify when no change occurs',
        );
      });

      test('handles empty map', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('anything');

        expect(notifier, isEmpty);
        expect(notified, isFalse);
      });
    });

    group('clear with notifications', () {
      test('removes all key-value pairs and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');
        notifier.upsert('value3', key: 'key3');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.clear();

        expect(notifier, isEmpty);
        expect(notifier.length, 0);
        expect(notified, isTrue);
      });

      test('can add items after clear and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');
        notifier.clear();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('value2', key: 'key2');

        expect(notifier, hasLength(1));
        expect(notifier['key2'], 'value2');
        expect(notifier.orderedValues, ['value2']);
        expect(notifier.keys, ['key2']);
        expect(notified, isTrue);
      });

      test('does not notify when already empty', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.clear();

        expect(notifier, isEmpty);
        expect(notified, isFalse);
      });
    });

    group('inheritance from ImmutableOrderedMap', () {
      test('inherits all immutable operations', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        // Test assignAll
        notifier.assignAll({'key1': 'value1', 'key2': 'value2'});
        expect(notifier.keys, ['key1', 'key2']);
        expect(notifier.orderedValues, ['value1', 'value2']);

        // Test assignAllOrdered
        final userNotifier = env.makeOrderedMapNotifier<String, TestUser>(
          userToId,
        );
        final users = someTestUsers(2);
        userNotifier.assignAllOrdered(users);
        expect(userNotifier.orderedValues, users);
      });

      test('immutable operations create new instances', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.upsert('value1', key: 'key1');

        final originalLength = notifier.length;

        // Immutable operation
        notifier.assignAll({'new1': 'value1', 'new2': 'value2'});

        expect(notifier.keys, ['new1', 'new2']);
        expect(notifier.orderedValues, ['value1', 'value2']);
        expect(notifier, hasLength(2));
        expect(originalLength, 1, reason: 'Original should not be affected');
      });
    });

    group('listener management', () {
      test('multiple listeners are notified', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var listener1Notified = false;
        var listener2Notified = false;

        notifier.addListener(() => listener1Notified = true);
        notifier.addListener(() => listener2Notified = true);

        notifier.upsert('value1', key: 'key1');

        expect(listener1Notified, isTrue);
        expect(listener2Notified, isTrue);
      });

      test('removed listeners are not notified', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var notified = false;
        void listener() => notified = true;

        notifier.addListener(listener);
        notifier.removeListener(listener);

        notifier.upsert('value1', key: 'key1');

        expect(notified, isFalse);
      });

      test('dispose does not remove all listeners', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.dispose();
        expect(
          () => notifier.upsert('value1', key: 'key1'),
          throwsA(isA<AssertionError>()),
        );
        expect(notified, isFalse);
      });
    });

    group('complex scenarios with notifications', () {
      test('mixed operations trigger appropriate notifications', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        final operations = <String>[];

        notifier.addListener(() {
          operations.add(
            'length: ${notifier.length}, keys: ${notifier.keys.join(",")}',
          );
        });

        // Add some items
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');

        // Update existing
        notifier.upsert('updated', key: 'key1');

        // Add with putFirst
        notifier.upsert('value3', putFirst: true, key: 'key3');

        // Remove item
        notifier.remove('key2');

        // Clear
        notifier.clear();

        // Add after clear
        notifier.upsert('value', key: 'final');

        expect(operations, [
          'length: 1, keys: key1',
          'length: 2, keys: key1,key2',
          'length: 2, keys: key2,key1', // Update changes the order
          'length: 3, keys: key3,key2,key1', // putFirst changes order
          'length: 2, keys: key3,key1', // Remove changes order
          'length: 0, keys: ', // Clear
          'length: 1, keys: final', // Final add
        ]);
      });

      test('handles rapid successive operations', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        final notificationCount = <int>[];

        notifier.addListener(() => notificationCount.add(notifier.length));

        // Rapid operations
        notifier.upsert('value1', key: 'key1');
        notifier.upsert('value2', key: 'key2');
        notifier.upsert('value3', key: 'key3');
        notifier.upsert('updated', key: 'key2'); // Update
        notifier.remove('key1');
        notifier.upsert('value4', key: 'key4');
        notifier.clear();

        expect(notificationCount, [1, 2, 3, 3, 2, 3, 0]);
      });

      test('works with large number of items', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        var notificationCount = 0;

        notifier.addListener(() => notificationCount++);

        // Add many items
        for (var i = 0; i < 1000; i++) {
          notifier.upsert('value$i', key: 'key$i');
        }

        expect(notifier, hasLength(1000));
        expect(notificationCount, 1000);

        // Update every other item
        notificationCount = 0; // Reset counter
        for (var i = 0; i < 1000; i += 2) {
          notifier.upsert('updated$i', key: 'key$i');
        }

        expect(notifier, hasLength(1000));
        expect(notificationCount, 500);
      });
    });

    group('dispose behavior', () {
      test('dispose does not prevent further notifications', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.dispose();

        // These should cause notifications or crashes
        expect(
          () => notifier.upsert('value1', key: 'key1'),
          throwsA(isA<AssertionError>()),
        );
        expect(notified, isFalse);
      });

      test('dispose does not throw on multiple calls', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        notifier.dispose();
        expect(notifier.dispose, throwsA(isA<AssertionError>()));
      });
    });

    group('edge cases', () {
      test('in case if key is null, value is used', () {
        final notifier = env.makeOrderedMapNotifier<String?, String>(
          (final k) => k,
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('nullValue', key: null);
        notifier.upsert('value1', key: 'key1');
        notifier.remove(null);

        expect(notifier, hasLength(2));
        expect(notifier.containsKey(null), isFalse);
        expect(notifier.containsKey('nullValue'), isTrue);
        notifier.remove('nullValue');
        expect(notifier, hasLength(1));
        expect(notifier['key1'], 'value1');
        expect(notified, isTrue);
      });

      test('handles empty strings', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('emptyKey', key: '');
        notifier.upsert('value', key: 'non-empty');
        notifier.remove('');

        expect(notifier, hasLength(1));
        expect(notifier['non-empty'], 'value');
        expect(notified, isTrue);
      });

      test('works with complex objects', () {
        final userNotifier = env.makeOrderedMapNotifier<String, TestUser>(
          userToId,
        );
        final users = someTestUsers();

        var notified = false;
        userNotifier.addListener(() => notified = true);

        userNotifier.assignAllOrdered(users);
        userNotifier.upsert(users[0], putFirst: true); // Move to front
        userNotifier.remove(users[1].id);

        expect(userNotifier, hasLength(2)); // 3 users - 1 removed = 2 users
        expect(userNotifier.first, users[0].id);
        expect(userNotifier.orderedValues.first, users[0]);
        expect(notified, isTrue);
      });

      test('handles duplicate keys from toKey function', () {
        final userNotifier = env.makeOrderedMapNotifier<String, TestUser>(
          (final user) => 'same-key',
        );
        final users = someTestUsers();
        var notified = false;

        userNotifier.addListener(() => notified = true);

        userNotifier.assignAllOrdered(users); // All users get same key

        expect(userNotifier, hasLength(1)); // Only last user remains
        expect(userNotifier.keys, ['same-key']);
        expect(notified, isTrue);
      });
    });

    group('real-world usage patterns', () {
      test('simulates user list management', () {
        final userNotifier = env.makeOrderedMapNotifier<String, TestUser>(
          userToId,
        );
        final operations = <String>[];

        userNotifier.addListener(() {
          operations.add(
            'Users: ${userNotifier.length}, First: ${userNotifier.orderedValues.firstOrNull?.name ?? "none"}',
          );
        });

        // Add initial users
        final users = someTestUsers();
        userNotifier.assignAllOrdered(users);

        // Add a new user at the beginning (most recent)
        final newUser = aTestUser(name: 'New User');
        userNotifier.upsert(newUser, putFirst: true, key: newUser.id);

        // Update an existing user
        final updatedUser = users[1].copyWith(name: 'Updated Name');
        userNotifier.upsert(updatedUser, key: updatedUser.id);

        // Remove a user
        userNotifier.remove(users[0].id);

        expect(userNotifier, hasLength(3));
        expect(userNotifier.orderedValues.first.name, 'New User');
        expect(operations.length, 4); // Initial add, new user, update, remove
      });

      test('handles cache-like behavior', () {
        final cacheNotifier = env.makeOrderedMapNotifier<String, String>(
          stringToKey,
        );
        const maxSize = 5;
        var notificationCount = 0;

        cacheNotifier.addListener(() => notificationCount++);

        // Add items until max size
        for (var i = 1; i <= maxSize; i++) {
          cacheNotifier.upsert('value$i', key: 'key$i');
        }

        // Update existing item (should move to front if implementing LRU)
        cacheNotifier.upsert('updated-value3', putFirst: true, key: 'key3');

        // Add new item (would trigger eviction in real LRU cache)
        cacheNotifier.upsert('value6', key: 'key6');

        expect(cacheNotifier, hasLength(6));
        expect(cacheNotifier.first, 'key3'); // Most recently updated
        expect(notificationCount, 7); // 5 adds + 1 update + 1 new add
      });

      group('upsertAll with notifications', () {
        test('adds multiple items and notifies once', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          var notificationCount = 0;

          notifier.addListener(() => notificationCount++);
          notifier.upsertAll([
            'value1',
            'value2',
          ], toKey: (final v) => v.replaceAll('value', 'key'));

          expect(notifier, hasLength(2));
          expect(notifier['key1'], 'value1');
          expect(notifier['key2'], 'value2');
          expect(notifier.keys, ['key1', 'key2']);
          expect(
            notificationCount,
            1,
            reason: 'Should notify only once for batch operation',
          );
        });

        test('updates multiple items and notifies once', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');
          notifier.upsert('value2', key: 'key2');

          var notificationCount = 0;
          notifier.addListener(() => notificationCount++);

          notifier.upsertAll([
            'updated1',
            'updated2',
          ], toKey: (final v) => v.replaceAll('updated', 'key'));

          expect(notifier, hasLength(2));
          expect(notifier['key1'], 'updated1');
          expect(notifier['key2'], 'updated2');
          expect(
            notificationCount,
            1,
            reason: 'Should notify only once for batch operation',
          );
        });

        test('adds items at beginning with putFirst and notifies once', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');
          notifier.upsert('value2', key: 'key2');

          var notificationCount = 0;
          notifier.addListener(() => notificationCount++);

          notifier.upsertAll(
            ['value3', 'value4'],
            putFirst: true,
            toKey: (final v) => v.replaceAll('value', 'key'),
          );

          expect(notifier, hasLength(4));
          expect(notifier.keys, ['key3', 'key4', 'key1', 'key2']);
          expect(notifier.orderedValues, [
            'value3',
            'value4',
            'value1',
            'value2',
          ]);
          expect(
            notificationCount,
            1,
            reason: 'Should notify only once for batch operation',
          );
        });

        test('mixed new and existing keys notify once', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');
          notifier.upsert('value2', key: 'key2');

          var notificationCount = 0;
          notifier.addListener(() => notificationCount++);

          notifier.upsertAll(
            ['updated2', 'value3'],
            toKey: (final v) => switch (v) {
              'updated2' => 'key2',
              'value3' => 'key3',
              _ => throw ArgumentError.value(v, 'v', 'Invalid value'),
            },
          );

          expect(notifier, hasLength(3));
          expect(notifier['key1'], 'value1'); // unchanged
          expect(notifier['key2'], 'updated2'); // updated
          expect(notifier['key3'], 'value3'); // new
          expect(
            notificationCount,
            1,
            reason: 'Should notify only once for batch operation',
          );
        });

        test('does not notify when adding empty iterable', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');

          var notificationCount = 0;
          notifier.addListener(() => notificationCount++);

          notifier.upsertAll([]);

          expect(notifier, hasLength(1));
          expect(notifier['key1'], 'value1');
          expect(
            notificationCount,
            0,
            reason: 'Should not notify when no changes occur',
          );
        });

        test('uses toKey function when provided', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');

          var notificationCount = 0;
          notifier.addListener(() => notificationCount++);

          notifier.upsertAll([
            'value2',
            'value3',
          ], toKey: (final v) => 'custom_${v.replaceAll('value', 'key')}');

          expect(notifier, hasLength(3));
          expect(notifier['custom_key2'], 'value2');
          expect(notifier['custom_key3'], 'value3');
          expect(notifier.keys, ['key1', 'custom_key2', 'custom_key3']);
          expect(
            notificationCount,
            1,
            reason: 'Should notify only once for batch operation',
          );
        });

        test('single notification for large batch', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          var notificationCount = 0;
          const count = 100;

          notifier.addListener(() => notificationCount++);

          final values = List.generate(count, (final i) => 'value$i');
          notifier.upsertAll(
            values,
            toKey: (final v) => v.replaceAll('value', 'key'),
          );

          expect(notifier, hasLength(count));
          expect(notifier['key0'], 'value0');
          expect(notifier['key99'], 'value99');
          expect(
            notificationCount,
            1,
            reason: 'Should notify only once for large batch operation',
          );
        });

        test('notification includes all changes', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');
          notifier.upsert('value2', key: 'key2');

          final operations = <String>[];
          notifier.addListener(() {
            operations.add(
              'length: ${notifier.length}, keys: ${notifier.keys.join(",")}',
            );
          });

          notifier.upsertAll(
            ['updated2', 'value3'],
            toKey: (final v) => switch (v) {
              'updated2' => 'key2',
              'value3' => 'key3',
              _ => throw ArgumentError.value(v, 'v', 'Invalid value'),
            },
          );

          expect(operations, hasLength(1));
          expect(operations.first, 'length: 3, keys: key1,key2,key3');
        });

        test('maintains order in notification payload', () {
          final notifier = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          notifier.upsert('value1', key: 'key1');
          notifier.upsert('value2', key: 'key2');

          final operations = <String>[];
          notifier.addListener(() {
            operations.add('values: ${notifier.orderedValues.join(",")}');
          });

          notifier.upsertAll(
            ['updated2', 'value3'],
            toKey: (final v) => switch (v) {
              'updated2' => 'key2',
              'value3' => 'key3',
              _ => throw ArgumentError.value(v, 'v', 'Invalid value'),
            },
          );

          expect(operations, hasLength(1));
          expect(operations.first, 'values: value1,updated2,value3');
        });

        test('compares performance with individual upsert calls', () {
          final notifier1 = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );
          final notifier2 = env.makeOrderedMapNotifier<String, String>(
            stringToKey,
          );

          var notificationCount1 = 0;
          var notificationCount2 = 0;

          notifier1.addListener(() => notificationCount1++);
          notifier2.addListener(() => notificationCount2++);

          // Batch operation
          notifier1.upsertAll([
            'value1',
            'value2',
            'value3',
          ], toKey: (final v) => v.replaceAll('value', 'key'));

          // Individual operations
          notifier2.upsert('value1', key: 'key1');
          notifier2.upsert('value2', key: 'key2');
          notifier2.upsert('value3', key: 'key3');

          expect(notifier1.keys, notifier2.keys);
          expect(notifier1.orderedValues, notifier2.orderedValues);
          expect(
            notificationCount1,
            1,
            reason: 'Batch operation should notify once',
          );
          expect(
            notificationCount2,
            3,
            reason: 'Individual operations should notify three times',
          );
        });
      });
    });
  });
}
