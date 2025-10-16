import 'package:flutter/foundation.dart';

import 'ordered_map.dart';

/// {@template ordered_map_notifier}
/// A reactive ordered map notifier that extends [ImmutableOrderedMap] with change notification capabilities.
///
/// This class combines the immutability guarantees of [ImmutableOrderedMap] with Flutter's
/// [ChangeNotifier] pattern, making it ideal for reactive UI programming. Any mutations
/// to the map automatically trigger [notifyListeners()], allowing widgets to rebuild
/// when the underlying data changes.
///
/// ```dart
/// class MyWidget extends StatefulWidget {
///   @override
///   State<MyWidget> createState() => _MyWidgetState();
/// }
///
/// class _MyWidgetState extends State<MyWidget> {
///   late final OrderedMapNotifier<String, User> mapNotifier;
///
///   @override
///   void initState() {
///     super.initState();
///     mapNotifier = OrderedMapNotifier<String, User>(toKey: (user) => user.id);
///     mapNotifier.addListener(() => setState(() {}));
///
///     // Add some initial data
///     mapNotifier.assignAllOrdered([
///       User(id: 'user1', name: 'Alice'),
///       User(id: 'user2', name: 'Bob'),
///     ]);
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return ListView.builder(
///       itemCount: mapNotifier.length,
///       itemBuilder: (context, index) {
///         final user = mapNotifier.orderedValues[index];
///         return ListTile(
///           title: Text(user.name),
///           subtitle: Text(user.id),
///         );
///       },
///     );
///   }
///
///   @override
///   void dispose() {
///     mapNotifier.dispose();
///     super.dispose();
///   }
/// }
/// ```
///
/// @ai Use this class in Flutter applications where you need reactive map updates.
/// Remember to call dispose() when the notifier is no longer needed to prevent memory leaks.
/// The [toKey] function is required for automatic key generation from values.
/// {@endtemplate}
class OrderedMapNotifier<K, V> extends ImmutableOrderedMap<K, V>
    with ChangeNotifier {
  /// {@template ordered_map_notifier_constructor}
  /// Creates a reactive ordered map notifier with the specified key extraction function.
  ///
  /// [toKey] - A function that converts values to their corresponding keys.
  /// This function is used internally to generate keys when values are added.
  ///
  /// @ai Provide a consistent [toKey] function to ensure reliable key generation and reactive updates.
  /// {@endtemplate}
  OrderedMapNotifier({super.toKey}) {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
  }

  /// {@template ordered_map_notifier_upsert}
  /// Inserts or updates the mapping for the specified [key] and [value] and notifies listeners.
  ///
  /// This method calls the superclass [upsert] method to perform the immutable update,
  /// then automatically calls [notifyListeners()] to trigger UI updates. The [putFirst]
  /// parameter controls whether the new key is placed at the beginning or end of the insertion order.
  ///
  /// @ai This method maintains immutability while providing reactive updates.
  /// Use [putFirst] to control the insertion position in the ordered sequence.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void upsert(final V value, {final bool putFirst = false, final K? key}) {
    super.upsert(value, putFirst: putFirst, key: key);
    notifyListeners();
  }

  /// {@template ordered_map_notifier_upsert_all}
  /// Inserts or updates multiple mappings from the provided [values] iterable and notifies listeners once.
  ///
  /// This method calls the superclass [upsertAll] method to perform the immutable batch update,
  /// then automatically calls [notifyListeners()] once at the end to trigger UI updates.
  /// This is more efficient than calling [upsert] multiple times as it only triggers
  /// a single notification after all items are processed.
  ///
  /// ```dart
  /// final notifier = OrderedMapNotifier<String, User>(toKey: (user) => user.id);
  ///
  /// // Efficient batch update with single notification
  /// notifier.upsertAll([
  ///   User(id: 'user1', name: 'Alice'),
  ///   User(id: 'user2', name: 'Bob'),
  ///   User(id: 'user3', name: 'Charlie'),
  /// ]);
  /// // Only one notifyListeners() call is made after all items are processed
  /// ```
  ///
  /// @ai Use this method for efficient batch updates in reactive contexts.
  /// The single notification at the end prevents excessive UI rebuilds during bulk operations.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void upsertAll(
    final Iterable<V> values, {
    final bool putFirst = false,
    final K? Function(V)? toKey,
  }) {
    super.upsertAll(values, putFirst: putFirst, toKey: toKey);
    if (values.isNotEmpty) {
      notifyListeners();
    }
  }

  /// {@template ordered_map_notifier_remove}
  /// Removes the mapping for the specified [key] if it exists and notifies listeners.
  ///
  /// This method calls the superclass [remove] method to perform the immutable update,
  /// then automatically calls [notifyListeners()] to trigger UI updates.
  ///
  /// @ai This method maintains immutability while providing reactive updates for removals.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void remove(final K key) {
    final hadKey = containsKey(key);
    super.remove(key);
    if (hadKey) {
      notifyListeners();
    }
  }

  /// {@template ordered_map_notifier_clear}
  /// Removes all mappings from this map and notifies listeners.
  ///
  /// This method calls the superclass [clear] method to perform the immutable update,
  /// then automatically calls [notifyListeners()] to trigger UI updates.
  ///
  /// @ai Use this method to reset the map while ensuring all listeners are notified.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void clear() {
    final hadItems = isNotEmpty;
    super.clear();
    if (hadItems) {
      notifyListeners();
    }
  }

  @override
  void assignAllOrdered(final Iterable<V> items) {
    super.assignAllOrdered(items);
    notifyListeners();
  }
}
