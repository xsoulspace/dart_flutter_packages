import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

/// {@template mutable_ordered_map_to_key_function}
/// A function signature for converting a value to its corresponding key in an ordered map.
///
/// This typedef is used by [ImmutableOrderedMap] to extract keys from values,
/// enabling automatic key generation and management.
///
/// @ai Implement this function to define how values should be mapped to keys in your ordered map.
/// {@endtemplate}
typedef MutableOrderedMapToKeyFunction<K, V> = K Function(V);

/// {@template mutable_ordered_map}
/// A mutable ordered map that maintains insertion order with key-based access.
///
/// This class provides a map-like interface while preserving the order in which key-value
/// pairs were added. It combines the benefits of both lists (ordered iteration) and maps
/// (fast key-based lookup). All operations maintain insertion order.
///
/// ```dart
/// final map = MutableOrderedMap<String, User>();
/// map.upsert('user1', User(id: 'user1', name: 'Alice'));
/// map.upsert('user2', User(id: 'user2', name: 'Bob'));
/// map.upsert('user3', User(id: 'user3', name: 'Charlie'));
///
/// print(map.orderedValues.map((u) => u.name)); // ['Alice', 'Bob', 'Charlie']
/// print(map['user2']?.name); // 'Bob'
/// ```
///
/// @ai Use this class when you need both ordered iteration and fast key-based access.
/// Consider using [ImmutableOrderedMap] if you need immutability guarantees.
/// {@endtemplate}
class MutableOrderedMap<K, V> with Iterable<K> {
  /// {@template mutable_ordered_map_constructor}
  /// Creates an empty mutable ordered map.
  ///
  /// The map starts with no key-value pairs and maintains insertion order
  /// for all subsequent operations.
  /// {@endtemplate}
  MutableOrderedMap();
  final _items = <K, V>{};
  final _orderedKeys = <K>{};

  /// {@template mutable_ordered_map_contains_key}
  /// Whether this map contains the specified [key].
  ///
  /// Returns `true` if the map contains a mapping for the specified key.
  ///
  /// @ai This method has O(1) average time complexity for hash-based keys.
  /// {@endtemplate}
  bool containsKey(final K key) => _items.containsKey(key);

  /// {@template mutable_ordered_map_values}
  /// Returns an iterable of all values in this map.
  ///
  /// The order of values is not guaranteed to match insertion order.
  /// Use [orderedValues] for ordered iteration.
  ///
  /// @ai Use this property for unordered value iteration or when order doesn't matter.
  /// {@endtemplate}
  Iterable<V> get values => _items.values;

  /// {@template mutable_ordered_map_entries}
  /// Returns an iterable of all key-value pairs in this map.
  ///
  /// The order of entries is not guaranteed to match insertion order.
  /// Use [orderedValues] for ordered value iteration.
  ///
  /// @ai Use this property when you need both keys and values together.
  /// {@endtemplate}
  Iterable<MapEntry<K, V>> get entries => _items.entries;

  @override
  Iterator<K> get iterator => _orderedKeys.iterator;

  /// {@template mutable_ordered_map_ordered_values}
  /// Returns a list of all values in insertion order.
  ///
  /// This property provides ordered access to values, which is not available
  /// through the standard [values] property.
  ///
  /// @ai Use this property when you need values in the order they were added.
  /// {@endtemplate}
  List<V> get orderedValues {
    final values = <V>[];
    for (final key in _orderedKeys) {
      final value = _items[key];
      if (value == null) continue;
      values.add(value);
    }
    return values;
  }

  /// {@template mutable_ordered_map_upsert}
  /// Inserts or updates the mapping for the specified [key] and [value].
  ///
  /// If the key already exists, its value is updated. If the key is new,
  /// it's added at the end of the insertion order. Subclasses can override
  /// this method to add validation logic.
  ///
  /// @ai Ensure proper validation is performed in subclasses before calling super.upsert().
  /// {@endtemplate}
  @mustCallSuper
  void upsert(final K key, final V value) {
    _items[key] = value;
    _orderedKeys.add(key);
  }

  /// {@template mutable_ordered_map_getter}
  /// Retrieves the value associated with the specified [key].
  ///
  /// Returns the value if the key exists, or `null` if the key is not found.
  ///
  /// @ai This provides the same functionality as standard map access.
  /// {@endtemplate}
  V? operator [](final K key) => _items[key];

  /// {@template mutable_ordered_map_remove}
  /// Removes the mapping for the specified [key] if it exists.
  ///
  /// The key and its associated value are removed from both the internal map
  /// and the ordered keys list, maintaining consistency.
  ///
  /// @ai This operation maintains the relative order of remaining items.
  /// {@endtemplate}
  @mustCallSuper
  void remove(final K key) {
    _items.remove(key);
    _orderedKeys.remove(key);
  }

  /// {@template mutable_ordered_map_clear}
  /// Removes all mappings from this map.
  ///
  /// After calling this method, the map will be empty but will retain
  /// its insertion order behavior for new additions.
  ///
  /// @ai Use this method when you need to reset the map but maintain its type.
  /// {@endtemplate}
  @mustCallSuper
  void clear() {
    _items.clear();
    _orderedKeys.clear();
  }
}

/// {@template immutable_ordered_map}
/// An immutable ordered map that maintains insertion order with key-based access and copy-on-write semantics.
///
/// This class provides an immutable wrapper around an ordered map where all mutating operations
/// create new immutable instances rather than modifying the existing collection. It requires
/// a [toKey] function to automatically generate keys from values, ensuring consistent
/// key generation and management.
///
/// ```dart
/// // Define a key extraction function
/// String userToKey(User user) => user.id;
///
/// final map = ImmutableOrderedMap<String, User>(toKey: userToKey);
/// map.assignAllOrdered([
///   User(id: 'user1', name: 'Alice'),
///   User(id: 'user2', name: 'Bob'),
///   User(id: 'user3', name: 'Charlie'),
/// ]);
///
/// print(map.orderedValues.map((u) => u.name)); // ['Alice', 'Bob', 'Charlie']
/// print(map['user2']?.name); // 'Bob'
///
/// // Immutable updates create new instances
/// final newMap = map..upsert('user4', User(id: 'user4', name: 'David'), putFirst: true);
/// print(newMap.orderedValues.map((u) => u.name)); // ['David', 'Alice', 'Bob', 'Charlie']
/// ```
///
/// @ai Use this class in reactive programming contexts where immutability is required.
/// The [toKey] function ensures consistent key generation from values.
/// {@endtemplate}
class ImmutableOrderedMap<K, V> with Iterable<K> {
  /// {@template immutable_ordered_map_constructor}
  /// Creates an immutable ordered map with the specified key extraction function.
  /// {@endtemplate}
  ///
  /// [toKey]
  /// {@macro immutable_ordered_map_to_key}
  ImmutableOrderedMap({required this.toKey});

  /// {@template immutable_ordered_map_to_key}
  /// A function that converts values to their corresponding keys.
  ///
  /// This function is used internally to generate keys when values are added.
  ///
  /// @ai Provide a consistent [toKey] function to ensure reliable key generation.
  /// {@endtemplate}
  // ignore: unsafe_variance
  final MutableOrderedMapToKeyFunction<K, V> toKey;
  Map<K, V> _items = const {};
  List<V>? _valuesListCache;
  void _setItems(final Map<K, V> items) {
    _items = items.unmodifiable;
    _valuesListCache = null;
  }

  Set<K> _orderedKeys = const {};
  List<K>? _orderedKeysListCache;
  void _setOrderedKeys(final Set<K> keys) {
    _orderedKeys = keys.unmodifiable;
    _orderedKeysListCache = null;
  }

  /// {@template immutable_ordered_map_contains_key}
  /// Whether this map contains the specified [key].
  ///
  /// Returns `true` if the map contains a mapping for the specified key.
  ///
  /// @ai This method has O(1) average time complexity for hash-based keys.
  /// {@endtemplate}
  bool containsKey(final K key) => _items.containsKey(key);

  @override
  Iterator<K> get iterator => _orderedKeys.iterator;

  /// {@template immutable_ordered_map_keys}
  /// Returns an unmodifiable list of all keys in insertion order.
  ///
  /// The keys are returned in the order they were added to the map,
  /// providing predictable iteration order.
  ///
  /// @ai Use this property when you need to iterate over keys in insertion order.
  /// {@endtemplate}
  List<K> get keys =>
      _orderedKeysListCache ??= _orderedKeys.toList().unmodifiable;

  /// {@template immutable_ordered_map_ordered_values}
  /// Returns an unmodifiable list of all values in insertion order.
  ///
  /// This property provides ordered access to values with caching for performance.
  /// The first call computes the ordered list, subsequent calls return the cached result
  /// until the map is modified.
  ///
  /// @ai This property is cached for performance - use it when you need ordered values frequently.
  /// {@endtemplate}
  List<V> get orderedValues {
    if (_valuesListCache != null) return _valuesListCache!;
    final values = <V>[];
    for (final key in _orderedKeys) {
      final value = _items[key];
      if (value == null) continue;
      values.add(value);
    }
    return _valuesListCache ??= values.unmodifiable;
  }

  /// {@template immutable_ordered_map_getter}
  /// Retrieves the value associated with the specified [key].
  ///
  /// Returns the value if the key exists, or `null` if the key is not found.
  ///
  /// @ai This provides standard map access functionality with null safety.
  /// {@endtemplate}
  V? operator [](final K key) => _items[key];

  /// {@template immutable_ordered_map_setter}
  /// Inserts or updates the mapping for the specified [key] and [value].
  ///
  /// This is a convenience operator that calls [upsert] with default parameters.
  /// The new key-value pair is added at the end of the insertion order.
  ///
  /// @ai Use this operator for simple insertions with default ordering behavior.
  /// {@endtemplate}
  void operator []=(final K key, final V value) => upsert(key, value);

  /// {@template immutable_ordered_map_assign_all}
  /// Replaces all items in this collection with the provided [map].
  ///
  /// This operation creates new unmodifiable collections internally, ensuring
  /// immutability while allowing bulk assignment operations. The keys from
  /// the provided map determine the new insertion order.
  ///
  /// @ai Use this method for bulk updates rather than multiple individual upsert() calls.
  /// {@endtemplate}
  void assignAll(final Map<K, V> map) {
    _setItems(map);
    _setOrderedKeys(map.keys.toSet());
  }

  /// {@template immutable_ordered_map_assign_all_ordered}
  /// Replaces all items in this collection with values from the provided [items] list.
  ///
  /// This method uses the [toKey] function to generate keys for each value,
  /// maintaining the order specified in the input list. This is useful when
  /// you have a list of values that need to be converted to a map with specific ordering.
  ///
  /// @ai Use this method when you have ordered data that needs key-based access.
  /// {@endtemplate}
  void assignAllOrdered(final List<V> items) {
    final newKeys = <K>{};
    final map = <K, V>{};
    for (final item in items) {
      final key = toKey(item);
      map[key] = item;
      newKeys.add(key);
    }
    _setItems(map);
    _setOrderedKeys(newKeys);
  }

  /// {@template immutable_ordered_map_upsert}
  /// Inserts or updates the mapping for the specified [key] and [value].
  ///
  /// This creates new unmodifiable collections containing all existing items plus the new mapping,
  /// maintaining immutability guarantees. The [putFirst] parameter controls whether the new
  /// key is placed at the beginning (`true`) or end (`false`) of the insertion order.
  ///
  /// @ai This operation has O(n) time complexity due to collection copying.
  /// Use [putFirst] to control insertion position in the ordered sequence.
  /// {@endtemplate}
  @mustCallSuper
  void upsert(final K key, final V value, {final bool putFirst = false}) {
    final items = {..._items, key: value}.unmodifiable;
    final putLast = !putFirst;
    final orderedKeys = {
      if (putFirst) key,
      ...{..._orderedKeys}..remove(key),
      if (putLast) key,
    }.unmodifiable;
    _setItems(items);
    _setOrderedKeys(orderedKeys);
  }

  /// {@template immutable_ordered_map_remove}
  /// Removes the mapping for the specified [key] if it exists.
  ///
  /// This creates new unmodifiable collections without the specified key,
  /// preserving the order of remaining items and maintaining immutability.
  ///
  /// @ai This operation has O(n) time complexity due to filtering and collection creation.
  /// {@endtemplate}
  @mustCallSuper
  void remove(final K key) {
    final items = {..._items}..remove(key);
    final orderedKeys = {..._orderedKeys}..remove(key);
    _setItems(items);
    _setOrderedKeys(orderedKeys);
  }

  /// {@template immutable_ordered_map_clear}
  /// Removes all mappings from this map.
  ///
  /// This creates new empty unmodifiable collections, maintaining immutability
  /// while resetting the map to its initial state.
  ///
  /// @ai Use this method to reset the map while preserving its immutable nature.
  /// {@endtemplate}
  @mustCallSuper
  void clear() {
    _setItems(<K, V>{});
    _setOrderedKeys(<K>{});
  }
}
