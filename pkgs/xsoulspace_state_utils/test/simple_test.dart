import 'package:flutter_test/flutter_test.dart' hide hasLength, isEmpty;

import 'support/harness.dart';

void main() {
  test('imports work correctly', () {
    final env = CollectionsTestEnv();

    // Test that we can create instances
    final mutableList = env.makeMutableOrderedList<String>();
    final immutableList = env.makeImmutableOrderedList<String>();
    final mutableMap = env.makeMutableOrderedMap<String, String>();
    final immutableMap = env.makeImmutableOrderedMap<String, String>(
      (final v) => v,
    );

    expect(mutableList, isNotNull);
    expect(immutableList, isNotNull);
    expect(mutableMap, isNotNull);
    expect(immutableMap, isNotNull);
  });
}
