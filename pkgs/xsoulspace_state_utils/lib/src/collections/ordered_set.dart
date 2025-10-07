import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

/// {@template mutable_ordered_set}
/// A mutable ordered collection that maintains insertion order and ensures uniqueness of elements.
///
/// This class extends [Iterable] and provides methods for adding, removing, and clearing items
/// while preserving the order in which they were added and ensuring no duplicates exist.
/// It's designed for scenarios where maintaining insertion order and uniqueness is important
/// and the collection needs to be modified frequently.
///
/// ```dart
/// final set = MutableOrderedSet<String>();
/// set.add('first');
/// set.add('second');
/// set.add('first'); // This won't be added as it's a duplicate
/// print(set); // ['first', 'second']
/// ```
///
/// @ai Use this class when you need a mutable collection with guaranteed insertion order and uniqueness.
/// Consider using [ImmutableOrderedSet] if you need immutability guarantees.
/// {@endtemplate}
class MutableOrderedSet<V> with Iterable<V> {
  final _items = <V>{};

  @override
  Iterator<V> get iterator => _items.iterator;

  /// {@template mutable_ordered_set_assign_all}
  /// Replaces all items in this collection with the provided [items].
  ///
  /// This operation creates a new set internally, ensuring
  /// immutability while allowing bulk assignment operations. Duplicates are removed.
  ///
  /// @ai Use this method for bulk updates rather than multiple individual add() calls.
  /// {@endtemplate}
  @mustCallSuper
  void assignAll(final Iterable<V> items) => _items
    ..clear()
    ..addAll(items);

  /// {@template mutable_ordered_set_add}
  /// Adds the specified [value] to this ordered set if it doesn't already exist.
  ///
  /// The item is appended to maintain insertion order only if it's not already present.
  /// Returns `true` if the value was added, `false` if it already existed.
  /// Subclasses can override this method to add validation logic.
  ///
  /// @ai Ensure proper validation is performed in subclasses before calling super.add().
  /// {@endtemplate}
  @mustCallSuper
  bool add(final V value) => _items.add(value);

  /// {@template mutable_ordered_set_remove}
  /// Removes the specified [value] from this ordered set if it exists.
  ///
  /// If the value exists, it is removed while maintaining the order of remaining items.
  /// Returns `true` if the value was removed, `false` if it didn't exist.
  ///
  /// @ai Consider the performance implications when removing items from large collections.
  /// {@endtemplate}
  @mustCallSuper
  bool remove(final V value) => _items.remove(value);

  /// {@template mutable_ordered_set_clear}
  /// Removes all items from this ordered set.
  ///
  /// After calling this method, the collection will be empty but will retain
  /// its insertion order and uniqueness behavior for new additions.
  ///
  /// @ai Use this method when you need to reset the collection but maintain its type.
  /// {@endtemplate}
  @mustCallSuper
  void clear() => _items.clear();

  /// {@template mutable_ordered_set_contains}
  /// Returns `true` if this set contains the specified [value].
  ///
  /// @ai Use this method to check for existence before performing operations.
  /// {@endtemplate}
  @override
  bool contains(final Object? value) => _items.contains(value);

  /// {@template mutable_ordered_set_length}
  /// Returns the number of elements in this set.
  ///
  /// @ai This is an O(1) operation for this implementation.
  /// {@endtemplate}
  @override
  int get length => _items.length;

  /// {@template mutable_ordered_set_is_empty}
  /// Returns `true` if this set contains no elements.
  ///
  /// @ai Use this property for conditional operations rather than checking length == 0.
  /// {@endtemplate}
  @override
  bool get isEmpty => _items.isEmpty;

  /// {@template mutable_ordered_set_is_not_empty}
  /// Returns `true` if this set contains one or more elements.
  ///
  /// @ai Use this property for conditional operations rather than checking length > 0.
  /// {@endtemplate}
  @override
  bool get isNotEmpty => _items.isNotEmpty;
}

/// {@template immutable_ordered_set}
/// An immutable ordered collection that maintains insertion order and uniqueness with copy-on-write semantics.
///
/// This class provides an immutable wrapper around an ordered set where all mutating operations
/// create new immutable instances rather than modifying the existing collection. This ensures
/// thread safety and predictable behavior in reactive programming scenarios while maintaining
/// both insertion order and uniqueness of elements.
///
/// ```dart
/// final set = ImmutableOrderedSet<String>();
/// final set1 = set.add('item1');
/// final set2 = set1.add('item2');
/// final set3 = set2.add('item1'); // Won't be added as it's a duplicate
/// print(set3); // ['item1', 'item2']
/// ```
///
/// @ai Use this class in reactive programming contexts where immutability is required.
/// Prefer [MutableOrderedSet] for scenarios where frequent mutations are expected.
/// {@endtemplate}
class ImmutableOrderedSet<V> with Iterable<V> {
  /// {@template immutable_ordered_set_constructor}
  /// Creates an immutable ordered set with optional initial items.
  ///
  /// [items] - The initial items to populate the set with. Defaults to an empty set.
  /// Duplicates in the provided items will be automatically removed, keeping only the first occurrence.
  /// The provided items will be made unmodifiable internally.
  /// {@endtemplate}
  ImmutableOrderedSet([final Iterable<V>? items])
    : _items = (items?.toSet() ?? <V>{}).unmodifiable;

  Set<V> _items;

  @override
  Iterator<V> get iterator => _items.iterator;

  /// {@template immutable_ordered_set_assign_all}
  /// Replaces all items in this collection with the provided [items].
  ///
  /// This operation creates a new unmodifiable set internally, ensuring
  /// immutability while allowing bulk assignment operations. Duplicates are removed.
  ///
  /// @ai Use this method for bulk updates rather than multiple individual add() calls.
  /// {@endtemplate}
  void assignAll(final Iterable<V> items) =>
      _items = items.toSet().unmodifiable;

  /// {@template immutable_ordered_set_add}
  /// Adds the specified [value] to this ordered set if it doesn't already exist.
  ///
  /// This creates a new unmodifiable set containing all existing items plus the new value
  /// maintaining immutability guarantees.
  ///
  /// Returns `true` if the value was added, `false` if it already existed.
  ///
  /// @ai This operation has O(n) time complexity due to set copying.
  /// {@endtemplate}
  @mustCallSuper
  bool add(final V value) {
    if (_items.contains(value)) return false;
    _items = {..._items, value}.unmodifiable;
    return true;
  }

  /// {@template immutable_ordered_set_remove}
  /// Removes the specified [value] from this ordered set if it exists.
  ///
  /// This creates a new unmodifiable set without the specified value,
  /// preserving the order of remaining items.
  /// Returns `true` if the value was removed, `false` if it didn't exist.
  ///
  /// @ai This operation has O(n) time complexity due to filtering and set creation.
  /// {@endtemplate}
  @mustCallSuper
  bool remove(final V value) {
    if (!_items.contains(value)) return false;
    final newItems = {..._items}..remove(value);
    _items = newItems.unmodifiable;
    return true;
  }

  /// {@template immutable_ordered_set_clear}
  /// Removes all items from this ordered set.
  ///
  /// This creates a new empty unmodifiable set, maintaining immutability.
  ///
  /// @ai Use this method to reset the collection while preserving its immutable nature.
  /// {@endtemplate}
  @mustCallSuper
  void clear() => _items = <V>{}.unmodifiable;

  /// {@template immutable_ordered_set_contains}
  /// Returns `true` if this set contains the specified [value].
  ///
  /// @ai Use this method to check for existence before performing operations.
  /// {@endtemplate}
  @override
  bool contains(final Object? value) => _items.contains(value);
}
