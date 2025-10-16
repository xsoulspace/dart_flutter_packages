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
typedef OrderedMapToKeyFunction<K, V> = K Function(V);

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
  MutableOrderedMap({this.toKey});
  final _items = <K, V>{};
  List<V>? _valuesListCache;
  final _orderedKeys = <K>{};

  /// {@template mutable_ordered_map_ordered_values}
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

  /// {@template mutable_ordered_map_to_key}
  /// A function that converts values to their corresponding keys.
  ///
  /// This function is used internally to generate keys when values are added.
  ///
  /// @ai Provide a consistent [toKey] function to ensure reliable key generation.
  /// {@endtemplate}
  // ignore: unsafe_variance
  final OrderedMapToKeyFunction<K, V>? toKey;

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
  void upsert(final V value, {final K? key}) {
    final effectiveKey = key ?? toKey?.call(value);
    if (effectiveKey == null) {
      throw ArgumentError.value(value, 'key', 'Key not provided');
    }
    _items[effectiveKey] = value;
    _orderedKeys.add(effectiveKey);
    _valuesListCache = null;
  }

  /// {@template mutable_ordered_map_upsert_all}
  /// Inserts or updates multiple mappings from the provided [values] iterable.
  ///
  /// This method efficiently processes multiple values in a single operation,
  /// performing a single cache invalidation at the end rather than after each item.
  /// The [toKey] function can be used to provide custom key extraction
  /// for this operation, overriding the default [toKey] function.
  ///
  /// ```dart
  /// final map = MutableOrderedMap<String, User>(toKey: (user) => user.id);
  ///
  /// // Using default toKey function
  /// map.upsertAll([
  ///   User(id: 'user1', name: 'Alice'),
  ///   User(id: 'user2', name: 'Bob'),
  /// ]);
  ///
  /// // Using custom key extraction
  /// map.upsertAll([
  ///   User(id: 'user3', name: 'Charlie'),
  ///   User(id: 'user4', name: 'David'),
  /// ], toKey: (user) => 'custom_${user.id}');
  /// ```
  ///
  /// @ai Use this method for efficient batch updates instead of multiple individual upsert() calls.
  /// The [toKey] parameter is useful when you need different key extraction for specific operations.
  /// {@endtemplate}
  void upsertAll(final Iterable<V> values, {final K? Function(V)? toKey}) {
    if (values.isEmpty) {
      return;
    }
    for (final value in values) {
      final effectiveKey = toKey?.call(value) ?? this.toKey?.call(value);
      if (effectiveKey == null) {
        throw ArgumentError.value(value, 'key', 'Key not provided');
      }
      _items[effectiveKey] = value;
      _orderedKeys.add(effectiveKey);
    }
    _valuesListCache = null; // Single cache invalidation
  }

  /// {@template mutable_ordered_map_update}
  /// Updates the value associated with the specified [key] using the provided
  /// [update] function.
  ///
  /// @ai Use this method to update the value associated with a key in the map.
  /// {@endtemplate}
  void update(
    final K key,
    final V Function(V) update, {
    final V Function()? ifAbsent,
  }) {
    final value = _items[key];
    V? updatedValue;
    if (value != null) {
      updatedValue = update(value);
    } else if (ifAbsent != null) {
      updatedValue = ifAbsent();
    }
    if (updatedValue != null) {
      upsert(updatedValue, key: key);
    } else {
      throw ArgumentError.value(key, 'value', 'Value not provided');
    }
    _valuesListCache = null;
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
    _valuesListCache = null;
  }

  /// {@template mutable_ordered_map_assign_all}
  /// Replaces all items in this collection with the provided [map].
  ///
  /// @ai Use this method for bulk updates rather than multiple individual upsert() calls.
  /// {@endtemplate}
  void assignAll(final Map<K, V> map) {
    _items
      ..clear()
      ..addAll(map);
    _orderedKeys
      ..clear()
      ..addAll(map.keys);
    _valuesListCache = null;
  }

  /// {@template mutable_ordered_map_assign_all_ordered}
  /// Replaces all items in this collection with values from the provided [items] list.
  ///
  /// This method uses the [toKey] function to generate keys for each value,
  /// maintaining the order specified in the input list. This is useful when
  /// you have a list of values that need to be converted to a map with specific ordering.
  ///
  /// @ai Use this method when you have ordered data that needs key-based access.
  /// {@endtemplate}
  void assignAllOrdered(final Iterable<V> items) {
    final newKeys = <K>{};
    final map = <K, V>{};
    for (final item in items) {
      final key = toKey?.call(item);
      if (key == null) {
        throw ArgumentError.value(item, 'item', 'Key not provided');
      }
      map[key] = item;
      newKeys.add(key);
    }
    _items
      ..clear()
      ..addAll(map);
    _orderedKeys
      ..clear()
      ..addAll(newKeys);
    _valuesListCache = null;
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
    _valuesListCache = null;
  }
}

/// {@template immutable_ordered_map}
/// An immutable ordered map that maintains insertion order with key-based access
/// and copy-on-write semantics.
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
  ImmutableOrderedMap({this.toKey});

  /// {@template immutable_ordered_map_to_key}
  /// A function that converts values to their corresponding keys.
  ///
  /// This function is used internally to generate keys when values are added.
  ///
  /// @ai Provide a consistent [toKey] function to ensure reliable key generation.
  /// {@endtemplate}
  // ignore: unsafe_variance
  final OrderedMapToKeyFunction<K, V>? toKey;
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
  void operator []=(final K key, final V value) => upsert(value, key: key);

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
  void assignAllOrdered(final Iterable<V> items) {
    final newKeys = <K>{};
    final map = <K, V>{};
    for (final item in items) {
      final key = toKey?.call(item);
      if (key == null) {
        throw ArgumentError.value(item, 'item', 'Key not provided');
      }
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
  void upsert(final V value, {final bool putFirst = false, final K? key}) {
    final effectiveKey = key ?? toKey?.call(value);
    if (effectiveKey == null) {
      throw ArgumentError.value(value, 'key', 'Key not provided');
    }
    final items = {..._items, effectiveKey: value}.unmodifiable;
    final putLast = !putFirst;
    final orderedKeys = {
      if (putFirst) effectiveKey,
      ...{..._orderedKeys}..remove(effectiveKey),
      if (putLast) effectiveKey,
    }.unmodifiable;
    _setItems(items);
    _setOrderedKeys(orderedKeys);
  }

  /// {@template immutable_ordered_map_upsert_all}
  /// Inserts or updates multiple mappings from the provided [values] iterable.
  ///
  /// This method efficiently processes multiple values in a single operation,
  /// creating new unmodifiable collections only once at the end. The [putFirst] parameter
  /// controls whether all new items are placed at the beginning or end of the insertion order.
  /// The [toKey] function can be used to provide custom key extraction for this operation.
  ///
  /// ```dart
  /// final map = ImmutableOrderedMap<String, User>(toKey: (user) => user.id);
  ///
  /// // Adding items at the end (default)
  /// map.upsertAll([
  ///   User(id: 'user1', name: 'Alice'),
  ///   User(id: 'user2', name: 'Bob'),
  /// ]);
  ///
  /// // Adding items at the beginning
  /// map.upsertAll([
  ///   User(id: 'user3', name: 'Charlie'),
  ///   User(id: 'user4', name: 'David'),
  /// ], putFirst: true);
  ///
  /// // Using custom key extraction
  /// map.upsertAll([
  ///   User(id: 'user5', name: 'Eve'),
  /// ], toKey: (user) => 'custom_${user.id}');
  /// ```
  ///
  /// @ai Use this method for efficient batch updates instead of multiple individual upsert() calls.
  /// When [putFirst] is true, all new items are placed at the front in the order they appear in the iterable.
  /// {@endtemplate}
  void upsertAll(
    final Iterable<V> values, {
    final bool putFirst = false,
    final K? Function(V)? toKey,
  }) {
    if (values.isEmpty) {
      return;
    }
    final newItems = {..._items};
    final oldKeys = {..._orderedKeys};
    final keysToAdd = <K>[];

    for (final value in values) {
      final effectiveKey = toKey?.call(value) ?? this.toKey?.call(value);
      if (effectiveKey == null) {
        throw ArgumentError.value(value, 'key', 'Key not provided');
      }
      newItems[effectiveKey] = value;
      if (putFirst) {
        oldKeys.remove(effectiveKey);
      }
      if (!oldKeys.contains(effectiveKey)) {
        keysToAdd.add(effectiveKey);
      }
    }

    final orderedKeys = {
      if (putFirst) ...keysToAdd,
      ...oldKeys,
      if (!putFirst) ...keysToAdd,
    };

    _setItems(newItems);
    _setOrderedKeys(orderedKeys);
  }

  /// {@template immutable_ordered_map_update}
  /// Updates the value associated with the specified [key] using the provided
  /// [update] function.
  ///
  /// If the key is not found, the [ifAbsent] function is called to provide
  /// a default value. If the [ifAbsent] function is not provided, an
  /// [ArgumentError] is thrown.
  ///
  /// @ai Use this method to update the value associated with a key in the map.
  /// {@endtemplate}
  void update(
    final K key,
    final V Function(V) update, {
    final V Function()? ifAbsent,
  }) {
    final items = {..._items};
    final value = items[key];
    V? updatedValue;
    if (value != null) {
      updatedValue = update(value);
    } else if (ifAbsent != null) {
      updatedValue = ifAbsent();
    }
    if (updatedValue != null) {
      upsert(updatedValue, key: key);
    } else {
      throw ArgumentError.value(key, 'value', 'Value not provided');
    }
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
