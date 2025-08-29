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
  OrderedMapNotifier({required super.toKey});

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
  void upsert(final K key, final V value, {final bool putFirst = false}) {
    super.upsert(key, value, putFirst: putFirst);
    notifyListeners();
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
  void assignAllOrdered(final List<V> items) {
    super.assignAllOrdered(items);
    notifyListeners();
  }
}
