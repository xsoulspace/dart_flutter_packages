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

  group('OrderedListNotifier', () {
    group('initialization', () {
      test('starts empty', () {
        final notifier = env.makeOrderedListNotifier<String>();
        expect(notifier, isEmpty);
        expect(notifier.length, 0);
      });

      test('can be used as ImmutableOrderedList', () {
        final notifier = env.makeOrderedListNotifier<String>();
        expect(notifier, isA<ImmutableOrderedList<String>>());
      });

      test('can be used as ChangeNotifier', () {
        final notifier = env.makeOrderedListNotifier<String>();
        expect(notifier, isA<ChangeNotifier>());
      });
    });

    group('add with notifications', () {
      test('adds item and notifies listeners', () {
        final notifier = env.makeOrderedListNotifier<String>();
        var notified = false;

        notifier.addListener(() => notified = true);
        notifier.add('first');

        expect(notifier, hasLength(1));
        expect(notifier.first, 'first');
        expect(notified, isTrue);
      });

      test('maintains insertion order', () {
        final notifier = env.makeOrderedListNotifier<String>();
        final notifications = <int>[];

        notifier.addListener(() => notifications.add(notifier.length));

        notifier.add('first');
        notifier.add('second');
        notifier.add('third');

        expect(notifier, containsInOrder(['first', 'second', 'third']));
        expect(notifications, [1, 2, 3]);
      });

      test('handles different types', () {
        final stringNotifier = env.makeOrderedListNotifier<String>();
        final intNotifier = env.makeOrderedListNotifier<int>();

        var stringNotified = false;
        var intNotified = false;

        stringNotifier.addListener(() => stringNotified = true);
        intNotifier.addListener(() => intNotified = true);

        stringNotifier.add('test');
        intNotifier.add(42);

        expect(stringNotifier.first, 'test');
        expect(intNotifier.first, 42);
        expect(stringNotified, isTrue);
        expect(intNotified, isTrue);
      });

      test('allows duplicate values', () {
        final notifier = env.makeOrderedListNotifier<String>();
        var notificationCount = 0;

        notifier.addListener(() => notificationCount++);

        notifier.add('duplicate');
        notifier.add('duplicate');

        expect(notifier, hasLength(2));
        expect(notifier, containsInOrder(['duplicate', 'duplicate']));
        expect(notificationCount, 2);
      });
    });

    group('addUnique with notifications', () {
      test('adds unique item and notifies listeners', () {
        final notifier = env.makeOrderedListNotifier<String>();
        var notified = false;

        notifier.addListener(() => notified = true);
        final result = notifier.addUnique('first');

        expect(result, isTrue);
        expect(notifier, hasLength(1));
        expect(notifier.first, 'first');
        expect(notified, isTrue);
      });

      test('does not add duplicate and does not notify', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('first');

        var notified = false;
        notifier.addListener(() => notified = true);

        final result = notifier.addUnique('first');

        expect(result, isFalse);
        expect(notifier, hasLength(1));
        expect(notified, isFalse);
      });

      test('maintains order with mixed unique and duplicate adds', () {
        final notifier = env.makeOrderedListNotifier<String>();
        final notifications = <int>[];

        notifier.addListener(() => notifications.add(notifier.length));

        notifier.add('first');
        notifier.addUnique('second'); // should add and notify
        notifier.addUnique('first'); // should not add, no notification
        notifier.add('third');

        expect(notifier, containsInOrder(['first', 'second', 'third']));
        expect(notifications, [1, 2, 3]); // Only notified for successful adds
        notifier.dispose();
      });
    });

    group('remove with notifications', () {
      test('removes item and notifies listeners', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('first');
        notifier.add('second');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('first');

        expect(notifier, hasLength(1));
        expect(notifier, containsInOrder(['second']));
        expect(notified, isTrue);
      });

      test('maintains order after removal', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('first');
        notifier.add('second');
        notifier.add('third');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('second'); // Remove middle item

        expect(notifier, containsInOrder(['first', 'third']));
        expect(notified, isTrue);
      });

      test('does nothing when item not found', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('first');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('nonexistent');

        expect(notifier, hasLength(1));
        expect(notifier.first, 'first');
        expect(
          notified,
          isFalse,
          reason: 'Should not notify when no change occurs',
        );
      });

      test('handles empty list', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.remove('anything');

        expect(notifier, isEmpty);
        expect(notified, isFalse);
      });
    });

    group('clear with notifications', () {
      test('removes all items and notifies listeners', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('first');
        notifier.add('second');
        notifier.add('third');

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.clear();

        expect(notifier, isEmpty);
        expect(notified, isTrue);
      });

      test('can add items after clear and notifies', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('first');
        notifier.clear();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.add('second');

        expect(notifier, hasLength(1));
        expect(notifier.first, 'second');
        expect(notified, isTrue);
      });

      test('does not notify when already empty', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.clear();

        expect(notifier, isEmpty);
        expect(notified, isFalse);
      });
    });

    group('listener management', () {
      test('multiple listeners are notified', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var listener1Notified = false;
        var listener2Notified = false;

        notifier.addListener(() => listener1Notified = true);
        notifier.addListener(() => listener2Notified = true);

        notifier.add('item');

        expect(listener1Notified, isTrue);
        expect(listener2Notified, isTrue);
      });

      test('removed listeners are not notified', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var notified = false;
        void listener() => notified = true;

        notifier.addListener(listener);
        notifier.removeListener(listener);

        notifier.add('item');

        expect(notified, isFalse);
      });

      test('dispose does not remove listeners and throws', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.dispose();
        expect(() => notifier.add('item'), throwsA(isA<AssertionError>()));
      });
    });

    group('inheritance from ImmutableOrderedList', () {
      test('inherits all immutable operations', () {
        final notifier = env.makeOrderedListNotifier<String>();

        // Test assignAll
        notifier.assignAll(['item1', 'item2']);
        expect(notifier, containsInOrder(['item1', 'item2']));

        // Test addUnique
        final result = notifier.addUnique('item3');
        expect(result, isTrue);
        expect(notifier, containsInOrder(['item1', 'item2', 'item3']));
      });

      test('immutable operations create new instances', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.add('original');

        final originalLength = notifier.length;

        // Immutable operation
        notifier.assignAll(['new1', 'new2']);

        expect(notifier, hasLength(2));
        expect(originalLength, 1, reason: 'Original should not be affected');
      });
    });

    group('complex scenarios with notifications', () {
      test('mixed operations trigger appropriate notifications', () {
        final notifier = env.makeOrderedListNotifier<String>();
        final operations = <String>[];

        notifier.addListener(() {
          operations.add('notified: length=${notifier.length}');
        });

        // Add some items
        notifier.add('first');
        notifier.add('second');

        // Try to add duplicate (should not notify)
        notifier.addUnique('first');

        // Remove item
        notifier.remove('second');

        // Clear
        notifier.clear();

        // Add after clear
        notifier.add('final');

        expect(operations, [
          'notified: length=1',
          'notified: length=2',
          'notified: length=1', // After removal
          'notified: length=0', // After clear
          'notified: length=1', // After final add
        ]);
      });

      test('handles rapid successive operations', () {
        final notifier = env.makeOrderedListNotifier<String>();
        final notificationCount = <int>[];

        notifier.addListener(() => notificationCount.add(notifier.length));

        // Rapid operations
        notifier.add('1');
        notifier.add('2');
        notifier.add('3');
        notifier.remove('2');
        notifier.add('4');
        notifier.clear();

        expect(notificationCount, [1, 2, 3, 2, 3, 0]);
      });

      test('works with large number of items', () {
        final notifier = env.makeOrderedListNotifier<int>();
        var notificationCount = 0;

        notifier.addListener(() => notificationCount++);

        // Add many items
        for (var i = 0; i < 1000; i++) {
          notifier.add(i);
        }

        expect(notifier, hasLength(1000));
        expect(notificationCount, 1000);

        // Remove every other item
        notificationCount = 0; // Reset counter
        for (var i = 0; i < 1000; i += 2) {
          notifier.remove(i);
        }

        expect(notifier, hasLength(500));
        expect(notificationCount, 500);
      });
    });

    group('dispose behavior', () {
      test('dispose throws on further operations', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.dispose();

        // These should throw after dispose
        expect(
          () => notifier.add('after-dispose'),
          throwsA(isA<AssertionError>()),
        );

        expect(notified, isFalse);
      });

      test('dispose does throw on multiple calls', () {
        final notifier = env.makeOrderedListNotifier<String>();
        notifier.dispose();
        expect(notifier.dispose, throwsA(isA<AssertionError>()));
      });
    });

    group('edge cases', () {
      test('handles null values', () {
        final notifier = env.makeOrderedListNotifier<String?>();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.add(null);
        notifier.add('not-null');
        notifier.remove(null);

        expect(notifier, hasLength(1));
        expect(notifier.first, 'not-null');
        expect(notified, isTrue);
      });

      test('handles empty strings', () {
        final notifier = env.makeOrderedListNotifier<String>();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.add('');
        notifier.add('non-empty');
        notifier.remove('');

        expect(notifier, hasLength(1));
        expect(notifier.first, 'non-empty');
        expect(notified, isTrue);
      });

      test('handles complex objects', () {
        final notifier = env.makeOrderedListNotifier<TestUser>();
        final users = someTestUsers();

        var notified = false;
        notifier.addListener(() => notified = true);

        notifier.assignAll(users);
        notifier.remove(users.first);

        expect(notifier, hasLength(2));
        expect(notifier.first, users[1]);
        expect(notified, isTrue);
      });
    });
  });
}
