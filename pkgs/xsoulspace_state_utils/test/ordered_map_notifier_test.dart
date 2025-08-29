import 'package:flutter/foundation.dart';
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

  group('OrderedMapNotifier', () {
    late String Function(TestUser) toKey;

    setUp(() {
      toKey = userToId;
    });

    group('initialization', () {
      test('starts empty', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        expect(notifier, isEmpty);
        expect(notifier.length, 0);
      });

      test('can be used as ImmutableOrderedMap', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        expect(notifier, isA<ImmutableOrderedMap<String, String>>());
      });

      test('can be used as ChangeNotifier', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        expect(notifier, isA<ChangeNotifier>());
      });

      test('requires toKey function', () {
        expect(
          () => OrderedMapNotifier<String, String>(toKey: null as dynamic),
          throwsA(isA<TypeError>()),
        );
      });
    });

    group('upsert with notifications', () {
      test('adds new key-value pair and notifies listeners', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        var notified = false;

        notifier.addListener(() => notified = true);
        notifier.upsert('key1', 'value1');

        expect(notifier, hasLength(1));
        expect(notifier['key1'], 'value1');
        expect(notifier.keys, ['key1']);
        expect(notified, isTrue);
      });

      test('maintains insertion order', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        final operations = <String>[];

        notifier.addListener(
          () => operations.add('keys: ${notifier.keys.join(",")}'),
        );
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');
        notifier.upsert('key3', 'value3');

        expect(notifier.keys, ['key1', 'key2', 'key3']);
        expect(notifier.orderedValues, ['value1', 'value2', 'value3']);
        expect(operations, [
          'keys: key1',
          'keys: key1,key2',
          'keys: key1,key2,key3',
        ]);
      });

      test('updates existing key and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('key1', 'updated');

        expect(notifier, hasLength(1));
        expect(notifier['key1'], 'updated');
        expect(notifier.keys, ['key1']);
        expect(notified, isTrue);
      });

      test('putFirst places key at beginning and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('key3', 'value3', putFirst: true);

        expect(notifier.keys, ['key3', 'key1', 'key2']);
        expect(notifier.orderedValues, ['value3', 'value1', 'value2']);
        expect(notified, isTrue);
      });

      test('maintains order when updating with putFirst', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('key1', 'updated', putFirst: true); // Move to front

        expect(notifier.keys, ['key1', 'key2']);
        expect(notifier.orderedValues, ['updated', 'value2']);
        expect(notified, isTrue);
      });
    });

    group('remove with notifications', () {
      test('removes existing key-value pair and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');

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
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');
        notifier.upsert('key3', 'value3');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('key2'); // Remove middle key

        expect(notifier.keys, ['key1', 'key3']);
        expect(notifier.orderedValues, ['value1', 'value3']);
        expect(notified, isTrue);
      });

      test('does nothing when key not found', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');

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
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('anything');

        expect(notifier, isEmpty);
        expect(notified, isFalse);
      });
    });

    group('clear with notifications', () {
      test('removes all key-value pairs and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');
        notifier.upsert('key3', 'value3');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.clear();

        expect(notifier, isEmpty);
        expect(notifier.length, 0);
        expect(notified, isTrue);
      });

      test('can add items after clear and notifies', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('key1', 'value1');
        notifier.clear();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('key2', 'value2');

        expect(notifier, hasLength(1));
        expect(notifier['key2'], 'value2');
        expect(notifier.keys, ['key2']);
        expect(notified, isTrue);
      });

      test('does not notify when already empty', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.clear();

        expect(notifier, isEmpty);
        expect(notified, isFalse);
      });
    });

    group('inheritance from ImmutableOrderedMap', () {
      test('inherits all immutable operations', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

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
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.upsert('original', 'value1');

        final originalLength = notifier.length;

        // Immutable operation
        notifier.assignAll({'new1': 'value1', 'new2': 'value2'});

        expect(notifier, hasLength(2));
        expect(originalLength, 1, reason: 'Original should not be affected');
      });
    });

    group('listener management', () {
      test('multiple listeners are notified', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var listener1Notified = false;
        var listener2Notified = false;

        notifier.addListener(() => listener1Notified = true);
        notifier.addListener(() => listener2Notified = true);

        notifier.upsert('key1', 'value1');

        expect(listener1Notified, isTrue);
        expect(listener2Notified, isTrue);
      });

      test('removed listeners are not notified', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var notified = false;
        void listener() => notified = true;

        notifier.addListener(listener);
        notifier.removeListener(listener);

        notifier.upsert('key1', 'value1');

        expect(notified, isFalse);
      });

      test('dispose removes all listeners', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.dispose();
        notifier.upsert('key1', 'value1'); // This should not crash

        expect(notified, isFalse);
      });
    });

    group('complex scenarios with notifications', () {
      test('mixed operations trigger appropriate notifications', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        final operations = <String>[];

        notifier.addListener(() {
          operations.add(
            'length: ${notifier.length}, keys: ${notifier.keys.join(",")}',
          );
        });

        // Add some items
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');

        // Update existing
        notifier.upsert('key1', 'updated');

        // Add with putFirst
        notifier.upsert('key3', 'value3', putFirst: true);

        // Remove item
        notifier.remove('key2');

        // Clear
        notifier.clear();

        // Add after clear
        notifier.upsert('final', 'value');

        expect(operations, [
          'length: 1, keys: key1',
          'length: 2, keys: key1,key2',
          'length: 2, keys: key1,key2', // Update doesn't change order
          'length: 3, keys: key3,key1,key2', // putFirst changes order
          'length: 2, keys: key3,key1', // Remove changes order
          'length: 0, keys: ', // Clear
          'length: 1, keys: final', // Final add
        ]);
      });

      test('handles rapid successive operations', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        final notificationCount = <int>[];

        notifier.addListener(() => notificationCount.add(notifier.length));

        // Rapid operations
        notifier.upsert('key1', 'value1');
        notifier.upsert('key2', 'value2');
        notifier.upsert('key3', 'value3');
        notifier.upsert('key2', 'updated'); // Update
        notifier.remove('key1');
        notifier.upsert('key4', 'value4');
        notifier.clear();

        expect(notificationCount, [1, 2, 3, 3, 2, 3, 0]);
      });

      test('works with large number of items', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        var notificationCount = 0;

        notifier.addListener(() => notificationCount++);

        // Add many items
        for (var i = 0; i < 1000; i++) {
          notifier.upsert('key$i', 'value$i');
        }

        expect(notifier, hasLength(1000));
        expect(notificationCount, 1000);

        // Update every other item
        notificationCount = 0; // Reset counter
        for (var i = 0; i < 1000; i += 2) {
          notifier.upsert('key$i', 'updated$i');
        }

        expect(notifier, hasLength(1000));
        expect(notificationCount, 500);
      });
    });

    group('dispose behavior', () {
      test('dispose prevents further notifications', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.dispose();

        // These should not cause notifications or crashes
        notifier.upsert('key1', 'value1');
        notifier.remove('nonexistent');
        notifier.clear();

        expect(notified, isFalse);
      });

      test('dispose handles multiple calls gracefully', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);
        notifier.dispose();
        expect(notifier.dispose, returnsNormally);
      });
    });

    group('edge cases', () {
      test('handles null keys', () {
        final notifier = env.makeOrderedMapNotifier<String?, String>(
          (final k) => k ?? 'null-key',
        );

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert(null, 'nullValue');
        notifier.upsert('key1', 'value1');
        notifier.remove(null);

        expect(notifier, hasLength(1));
        expect(notifier.containsKey(null), isFalse);
        expect(notifier['key1'], 'value1');
        expect(notified, isTrue);
      });

      test('handles empty strings', () {
        final notifier = env.makeOrderedMapNotifier<String, String>(toKey);

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.upsert('', 'emptyKey');
        notifier.upsert('non-empty', 'value');
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
        userNotifier.upsert(
          users[0].id,
          users[0],
          putFirst: true,
        ); // Move to front
        userNotifier.remove(users[1].id);

        expect(userNotifier, hasLength(3));
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
        expect(notifier, isTrue);
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
        userNotifier.upsert(newUser.id, newUser, putFirst: true);

        // Update an existing user
        final updatedUser = users[1].copyWith(name: 'Updated Name');
        userNotifier.upsert(updatedUser.id, updatedUser);

        // Remove a user
        userNotifier.remove(users[0].id);

        expect(userNotifier, hasLength(3));
        expect(userNotifier.orderedValues.first.name, 'New User');
        expect(operations.length, 4); // Initial add, new user, update, remove
      });

      test('handles cache-like behavior', () {
        final cacheNotifier = env.makeOrderedMapNotifier<String, String>(
          (final key) => key,
        );
        const maxSize = 5;
        var notificationCount = 0;

        cacheNotifier.addListener(() => notificationCount++);

        // Add items until max size
        for (var i = 1; i <= maxSize; i++) {
          cacheNotifier.upsert('key$i', 'value$i');
        }

        // Update existing item (should move to front if implementing LRU)
        cacheNotifier.upsert('key3', 'updated-value3', putFirst: true);

        // Add new item (would trigger eviction in real LRU cache)
        cacheNotifier.upsert('key6', 'value6');

        expect(cacheNotifier, hasLength(6));
        expect(cacheNotifier.first, 'key3'); // Most recently updated
        expect(notificationCount, 7); // 5 adds + 1 update + 1 new add
      });
    });
  });
}
