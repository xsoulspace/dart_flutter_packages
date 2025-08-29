import 'package:test/test.dart';
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

/// {@template collection_matchers}
/// Custom matchers for testing collection classes and their behaviors.
///
/// These matchers provide clear, readable assertions for common collection
/// testing scenarios with descriptive failure messages.
/// {@endtemplate}

/// {@template has_length_matcher}
/// Matcher that checks if a collection has the expected length.
/// {@endtemplate}
Matcher hasLength(final int expected) => _HasLengthMatcher(expected);

class _HasLengthMatcher extends Matcher {
  const _HasLengthMatcher(this.expected);

  final int expected;

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! Iterable) return false;
    return item.length == expected;
  }

  @override
  Description describe(final Description description) =>
      description.add('has length $expected');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! Iterable) {
      return mismatchDescription.add('is not an Iterable');
    }
    return mismatchDescription.add('has length ${item.length}');
  }
}

/// {@template is_empty_matcher}
/// Matcher that checks if a collection is empty.
/// {@endtemplate}
const Matcher isEmpty = _IsEmptyMatcher();

class _IsEmptyMatcher extends Matcher {
  const _IsEmptyMatcher();

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! Iterable) return false;
    return item.isEmpty;
  }

  @override
  Description describe(final Description description) =>
      description.add('is empty');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! Iterable) {
      return mismatchDescription.add('is not an Iterable');
    }
    return mismatchDescription.add('has ${item.length} items');
  }
}

/// {@template contains_in_order_matcher}
/// Matcher that checks if a collection contains the expected items in order.
/// {@endtemplate}
Matcher containsInOrder(final List<Object?> expected) =>
    _ContainsInOrderMatcher(expected);

class _ContainsInOrderMatcher extends Matcher {
  const _ContainsInOrderMatcher(this.expected);

  final List<Object?> expected;

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! Iterable) return false;
    final list = item.toList();
    if (list.length != expected.length) return false;

    for (var i = 0; i < expected.length; i++) {
      if (list[i] != expected[i]) return false;
    }
    return true;
  }

  @override
  Description describe(final Description description) =>
      description.add('contains $expected in order');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! Iterable) {
      return mismatchDescription.add('is not an Iterable');
    }
    final list = item.toList();
    return mismatchDescription.add('contains $list');
  }
}

/// {@template has_key_matcher}
/// Matcher that checks if a map contains a specific key.
/// {@endtemplate}
Matcher hasKey(final Object? key) => _HasKeyMatcher(key);

class _HasKeyMatcher extends Matcher {
  const _HasKeyMatcher(this.key);

  final Object? key;

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! Map) return false;
    return item.containsKey(key);
  }

  @override
  Description describe(final Description description) =>
      description.add('has key $key');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! Map) {
      return mismatchDescription.add('is not a Map');
    }
    return mismatchDescription.add('does not contain key $key');
  }
}

/// {@template has_value_matcher}
/// Matcher that checks if a map contains a specific value.
/// {@endtemplate}
Matcher hasValue(final Object? value) => _HasValueMatcher(value);

class _HasValueMatcher extends Matcher {
  const _HasValueMatcher(this.value);

  final Object? value;

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! Map) return false;
    return item.containsValue(value);
  }

  @override
  Description describe(final Description description) =>
      description.add('has value $value');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! Map) {
      return mismatchDescription.add('is not a Map');
    }
    return mismatchDescription.add('does not contain value $value');
  }
}

/// {@template ordered_map_has_ordered_values_matcher}
/// Matcher that checks if an ordered map has the expected values in order.
/// {@endtemplate}
Matcher hasOrderedValues(final List<Object?> expected) =>
    _HasOrderedValuesMatcher(expected);

class _HasOrderedValuesMatcher extends Matcher {
  const _HasOrderedValuesMatcher(this.expected);

  final List<Object?> expected;

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! MutableOrderedMap && item is! ImmutableOrderedMap) {
      return false;
    }

    final values = item is MutableOrderedMap
        ? item.orderedValues
        : (item! as ImmutableOrderedMap).orderedValues;

    if (values.length != expected.length) return false;

    for (var i = 0; i < expected.length; i++) {
      if (values[i] != expected[i]) return false;
    }
    return true;
  }

  @override
  Description describe(final Description description) =>
      description.add('has ordered values $expected');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! MutableOrderedMap && item is! ImmutableOrderedMap) {
      return mismatchDescription.add('is not an OrderedMap');
    }

    final values = item is MutableOrderedMap
        ? item.orderedValues
        : (item! as ImmutableOrderedMap).orderedValues;

    return mismatchDescription.add('has ordered values $values');
  }
}

/// {@template ordered_map_has_keys_in_order_matcher}
/// Matcher that checks if an ordered map has keys in the expected order.
/// {@endtemplate}
Matcher hasKeysInOrder(final List<Object?> expected) =>
    _HasKeysInOrderMatcher(expected);

class _HasKeysInOrderMatcher extends Matcher {
  const _HasKeysInOrderMatcher(this.expected);

  final List<Object?> expected;

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! MutableOrderedMap && item is! ImmutableOrderedMap) {
      return false;
    }

    final keys = item is MutableOrderedMap
        ? item.toList()
        : (item! as ImmutableOrderedMap).keys;

    if (keys.length != expected.length) return false;

    var i = 0;
    for (final key in keys) {
      if (key != expected[i]) return false;
      i++;
    }
    return true;
  }

  @override
  Description describe(final Description description) =>
      description.add('has keys in order $expected');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! MutableOrderedMap && item is! ImmutableOrderedMap) {
      return mismatchDescription.add('is not an OrderedMap');
    }

    final keys = item is MutableOrderedMap
        ? item.toList()
        : (item! as ImmutableOrderedMap).keys;

    return mismatchDescription.add('has keys ${keys.toList()}');
  }
}

/// {@template contains_unique_items_matcher}
/// Matcher that checks if a collection contains only unique items.
/// {@endtemplate}
const Matcher containsUniqueItems = _ContainsUniqueItemsMatcher();

class _ContainsUniqueItemsMatcher extends Matcher {
  const _ContainsUniqueItemsMatcher();

  @override
  bool matches(final Object? item, final Map matchState) {
    if (item is! Iterable) return false;
    final set = <Object?>{};
    for (final element in item) {
      if (!set.add(element)) return false;
    }
    return true;
  }

  @override
  Description describe(final Description description) =>
      description.add('contains only unique items');

  @override
  Description describeMismatch(
    final Object? item,
    final Description mismatchDescription,
    final Map matchState,
    final bool verbose,
  ) {
    if (item is! Iterable) {
      return mismatchDescription.add('is not an Iterable');
    }

    final duplicates = <Object?, int>{};
    final seen = <Object?>{};

    for (final element in item) {
      if (!seen.add(element)) {
        duplicates[element] = (duplicates[element] ?? 0) + 1;
      }
    }

    if (duplicates.isEmpty) {
      return mismatchDescription.add('is empty');
    }

    return mismatchDescription.add('contains duplicates: $duplicates');
  }
}
