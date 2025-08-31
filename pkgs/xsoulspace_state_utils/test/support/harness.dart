import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

export 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

/// {@template collections_test_env}
/// Test environment for collections classes providing factories and test utilities.
///
/// This harness provides a consistent way to create and test collection instances
/// with proper setup and teardown for each test case.
/// {@endtemplate}
class CollectionsTestEnv {
  /// {@template collections_test_env_set_up}
  /// Sets up the test environment with any necessary initialization.
  ///
  /// Call this in setUp() before each test.
  /// {@endtemplate}
  void setUp() {
    // Setup code if needed for future extensions
  }

  /// {@template collections_test_env_tear_down}
  /// Cleans up the test environment after each test.
  ///
  /// Call this in tearDown() after each test.
  /// {@endtemplate}
  void tearDown() {
    // Cleanup code if needed for future extensions
  }

  // Factory methods for creating test subjects

  /// {@template collections_test_env_make_mutable_ordered_list}
  /// Creates a new MutableOrderedList for testing.
  ///
  /// @ai Use this factory to ensure consistent test setup for MutableOrderedList instances.
  /// {@endtemplate}
  MutableOrderedList<V> makeMutableOrderedList<V>() => MutableOrderedList<V>();

  /// {@template collections_test_env_make_immutable_ordered_list}
  /// Creates a new ImmutableOrderedList for testing.
  ///
  /// @ai Use this factory to ensure consistent test setup for ImmutableOrderedList instances.
  /// {@endtemplate}
  ImmutableOrderedList<V> makeImmutableOrderedList<V>([
    final List<V> initial = const [],
  ]) => ImmutableOrderedList<V>(initial);

  /// {@template collections_test_env_make_ordered_list_notifier}
  /// Creates a new OrderedListNotifier for testing.
  ///
  /// @ai Use this factory to ensure consistent test setup for OrderedListNotifier instances.
  /// {@endtemplate}
  OrderedListNotifier<V> makeOrderedListNotifier<V>() =>
      OrderedListNotifier<V>();

  /// {@template collections_test_env_make_mutable_ordered_set}
  /// Creates a new MutableOrderedSet for testing.
  ///
  /// @ai Use this factory to ensure consistent test setup for MutableOrderedSet instances.
  /// {@endtemplate}
  MutableOrderedSet<V> makeMutableOrderedSet<V>() => MutableOrderedSet<V>();

  /// {@template collections_test_env_make_immutable_ordered_set}
  /// Creates a new ImmutableOrderedSet for testing.
  ///
  /// @ai Use this factory to ensure consistent test setup for ImmutableOrderedSet instances.
  /// {@endtemplate}
  ImmutableOrderedSet<V> makeImmutableOrderedSet<V>([
    final Iterable<V>? initial,
  ]) => ImmutableOrderedSet<V>(initial);

  /// {@template collections_test_env_make_mutable_ordered_map}
  /// Creates a new MutableOrderedMap for testing.
  ///
  /// @ai Use this factory to ensure consistent test setup for MutableOrderedMap instances.
  /// {@endtemplate}
  MutableOrderedMap<K, V> makeMutableOrderedMap<K, V>(
    final OrderedMapToKeyFunction<K, V> toKey,
  ) => MutableOrderedMap<K, V>(toKey: toKey);

  /// {@template collections_test_env_make_immutable_ordered_map}
  /// Creates a new ImmutableOrderedMap for testing with the specified key function.
  ///
  /// @ai Use this factory to ensure consistent test setup for ImmutableOrderedMap instances.
  /// {@endtemplate}
  ImmutableOrderedMap<K, V> makeImmutableOrderedMap<K, V>(
    final OrderedMapToKeyFunction<K, V> toKey,
  ) => ImmutableOrderedMap<K, V>(toKey: toKey);

  /// {@template collections_test_env_make_ordered_map_notifier}
  /// Creates a new OrderedMapNotifier for testing with the specified key function.
  ///
  /// @ai Use this factory to ensure consistent test setup for OrderedMapNotifier instances.
  /// {@endtemplate}
  OrderedMapNotifier<K, V> makeOrderedMapNotifier<K, V>(
    final OrderedMapToKeyFunction<K, V> toKey,
  ) => OrderedMapNotifier<K, V>(toKey: toKey);
}
