import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

/// {@template mutable_ordered_list}
/// A mutable ordered collection that maintains insertion order and provides list-like operations.
///
/// This class extends [Iterable] and provides methods for adding, removing, and clearing items
/// while preserving the order in which they were added. It's designed for scenarios where
/// maintaining insertion order is important and the collection needs to be modified frequently.
///
/// ```dart
/// final list = MutableOrderedList<String>();
/// list.add('first');
/// list.add('second');
/// list.add('third');
/// print(list); // ['first', 'second', 'third']
/// ```
///
/// @ai Use this class when you need a mutable collection with guaranteed insertion order.
/// Consider using [ImmutableOrderedList] if you need immutability guarantees.
/// {@endtemplate}
class MutableOrderedList<V> with Iterable<V> {
  final _items = <V>[];

  @override
  Iterator<V> get iterator => _items.iterator;

  /// {@template mutable_ordered_list_add}
  /// Adds the specified [value] to the end of this ordered list.
  ///
  /// The item is appended to maintain insertion order. Subclasses can override
  /// this method to add validation logic.
  ///
  /// @ai Ensure proper validation is performed in subclasses before calling super.add().
  /// {@endtemplate}
  @mustCallSuper
  void add(final V value) => _items.add(value);

  /// {@template mutable_ordered_list_remove}
  /// Removes the first occurrence of the specified [value] from this ordered list.
  ///
  /// If the value appears multiple times, only the first occurrence is removed
  /// while maintaining the order of remaining items.
  ///
  /// @ai Consider the performance implications when removing items from large collections.
  /// {@endtemplate}
  @mustCallSuper
  void remove(final V value) => _items.remove(value);

  /// {@template mutable_ordered_list_clear}
  /// Removes all items from this ordered list.
  ///
  /// After calling this method, the collection will be empty but will retain
  /// its insertion order behavior for new additions.
  ///
  /// @ai Use this method when you need to reset the collection but maintain its type.
  /// {@endtemplate}
  @mustCallSuper
  void clear() => _items.clear();

  /// {@template mutable_ordered_list_getter}
  /// Retrieves the item at the specified [index].
  ///
  /// @ai Use this operator for standard list access.
  /// {@endtemplate}
  V operator [](final int index) => _items[index];

  /// {@template mutable_ordered_list_setter}
  /// Sets the item at the specified [index] to the specified [value].
  ///
  /// @ai Use this operator for standard list mutation.
  /// {@endtemplate}
  void operator []=(final int index, final V value) => _items[index] = value;
}

/// {@template immutable_ordered_list}
/// An immutable ordered collection that maintains insertion order with copy-on-write semantics.
///
/// This class provides an immutable wrapper around an ordered list where all mutating operations
/// create new immutable instances rather than modifying the existing collection. This ensures
/// thread safety and predictable behavior in reactive programming scenarios.
///
/// ```dart
/// final list = ImmutableOrderedList<String>();
/// list.add('item1');
/// list.add('item2');
/// print(list); // ['item1', 'item2']
///
/// final newList = list..add('item3');
/// print(newList); // ['item1', 'item2', 'item3']
/// ```
///
/// @ai Use this class in reactive programming contexts where immutability is required.
/// Prefer [MutableOrderedList] for scenarios where frequent mutations are expected.
/// {@endtemplate}
class ImmutableOrderedList<V> with Iterable<V> {
  /// {@template immutable_ordered_list_constructor}
  /// Creates an immutable ordered list with optional initial items.
  ///
  /// [items] - The initial items to populate the list with. Defaults to an empty list.
  /// The provided items will be made unmodifiable internally.
  /// {@endtemplate}
  ImmutableOrderedList([this._items = const []]);
  List<V> _items;

  @override
  Iterator<V> get iterator => _items.iterator;

  /// {@template immutable_ordered_list_getter}
  /// Retrieves the item at the specified [index].
  ///
  /// @ai Use this operator for standard list access.
  /// {@endtemplate}
  V operator [](final int index) => _items[index];

  /// {@template immutable_ordered_list_setter}
  /// Sets the item at the specified [index] to the specified [value].
  ///
  /// @ai Use this operator for standard list access.
  /// {@endtemplate}
  void operator []=(final int index, final V value) {
    _items = ([..._items]..[index] = value).unmodifiable;
  }

  /// {@template immutable_ordered_list_assign_all}
  /// Replaces all items in this collection with the provided [items].
  ///
  /// This operation creates a new unmodifiable list internally, ensuring
  /// immutability while allowing bulk assignment operations.
  ///
  /// @ai Use this method for bulk updates rather than multiple individual add() calls.
  /// {@endtemplate}
  void assignAll(final List<V> items) => _items = items.unmodifiable;

  /// {@template immutable_ordered_list_add}
  /// Adds the specified [value] to the end of this ordered list.
  ///
  /// This creates a new unmodifiable list containing all existing items plus the new value,
  /// maintaining immutability guarantees.
  ///
  /// @ai This operation has O(n) time complexity due to list copying.
  /// {@endtemplate}
  @mustCallSuper
  void add(final V value) => _items = [..._items, value].unmodifiable;

  /// {@template immutable_ordered_list_add_unique}
  /// Adds the specified [value] to the end of this ordered list if it doesn't already exist.
  ///
  /// Returns `true` if the value was added, `false` if it already existed.
  /// This method ensures uniqueness while maintaining insertion order.
  ///
  /// @ai Use this method when you need set-like behavior with ordered insertion.
  /// {@endtemplate}
  @mustCallSuper
  bool addUnique(final V value) {
    // TODO(arenukvern): rewrite to use index
    if (_items.contains(value)) return false;
    add(value);
    return true;
  }

  /// {@template immutable_ordered_list_remove}
  /// Removes the first occurrence of the specified [value] from this ordered list.
  ///
  /// This creates a new unmodifiable list without the specified value,
  /// preserving the order of remaining items.
  ///
  /// @ai This operation has O(n) time complexity due to filtering and list creation.
  /// {@endtemplate}
  @mustCallSuper
  void remove(final V value) {
    final index = _items.indexOf(value);
    if (index == -1) return;
    final newItems = [..._items]..removeAt(index);
    _items = newItems.unmodifiable;
  }

  /// {@template immutable_ordered_list_remove_all}
  /// Removes all occurrences of the specified [value] from this ordered list.
  ///
  /// This creates a new unmodifiable list without the specified value,
  /// preserving the order of remaining items.
  ///
  /// @ai This operation has O(n) time complexity due to filtering and list creation.
  /// {@endtemplate}
  @mustCallSuper
  void removeAll(final V value) =>
      _items = [..._items].where((final v) => v != value).toList().unmodifiable;

  /// {@template immutable_ordered_list_clear}
  /// Removes all items from this ordered list.
  ///
  /// This creates a new empty unmodifiable list, maintaining immutability.
  ///
  /// @ai Use this method to reset the collection while preserving its immutable nature.
  /// {@endtemplate}
  @mustCallSuper
  void clear() => _items = <V>[].unmodifiable;
}
