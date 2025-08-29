/// {@template test_builders}
/// Test data builders for creating common test objects and scenarios.
///
/// These builders provide sensible defaults and allow customization only for
/// the properties that matter for each specific test case.
/// {@endtemplate}
library;

// Simple test data classes
class TestItem {
  const TestItem({required this.id, required this.name, this.value = 0});

  final String id;
  final String name;
  final int value;

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is TestItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          value == other.value;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ value.hashCode;

  @override
  String toString() => 'TestItem(id: $id, name: $name, value: $value)';
}

class TestUser {
  const TestUser({
    required this.id,
    required this.name,
    this.email,
    this.age = 25,
  });

  final String id;
  final String name;
  final String? email;
  final int age;

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is TestUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          email == other.email &&
          age == other.age;

  @override
  int get hashCode =>
      id.hashCode ^ name.hashCode ^ email.hashCode ^ age.hashCode;

  @override
  String toString() =>
      'TestUser(id: $id, name: $name, email: $email, age: $age)';
}

// Key extraction functions for test users
String userToId(final TestUser user) => user.id;
String userToName(final TestUser user) => user.name;

/// {@template test_item_builders}
/// Builders for creating TestItem instances with sensible defaults.
/// {@endtemplate}

/// Creates a TestItem with sensible defaults.
/// Specify only the properties that matter for your test case.
TestItem aTestItem({final String? id, final String? name, final int? value}) =>
    TestItem(
      id: id ?? 'test-id-${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? 'test-name',
      value: value ?? 42,
    );

/// Creates a list of TestItems for testing collections.
List<TestItem> someTestItems([
  final int count = 3,
  final String prefix = 'item',
]) => List.generate(
  count,
  (final i) => TestItem(
    id: '$prefix-${i + 1}',
    name: '$prefix-name-${i + 1}',
    value: (i + 1) * 10,
  ),
);

/// {@template test_user_builders}
/// Builders for creating TestUser instances with sensible defaults.
/// {@endtemplate}

/// Creates a TestUser with sensible defaults.
/// Specify only the properties that matter for your test case.
TestUser aTestUser({
  final String? id,
  final String? name,
  final String? email,
  final int? age,
}) => TestUser(
  id: id ?? 'user-${DateTime.now().millisecondsSinceEpoch}',
  name: name ?? 'Test User',
  email: email ?? 'test@example.com',
  age: age ?? 25,
);

/// Creates a list of TestUsers for testing collections.
List<TestUser> someTestUsers([
  final int count = 3,
  final String prefix = 'user',
]) => List.generate(
  count,
  (final i) => TestUser(
    id: '$prefix-${i + 1}',
    name: '$prefix-name-${i + 1}',
    email: '$prefix${i + 1}@example.com',
    age: 20 + i,
  ),
);

/// {@template string_list_builders}
/// Builders for creating string lists for testing.
/// {@endtemplate}

/// Creates a list of strings with the specified count.
List<String> someStrings([
  final int count = 3,
  final String prefix = 'string',
]) => List.generate(count, (final i) => '$prefix-${i + 1}');

/// Creates a single string with a timestamp to ensure uniqueness.
String aString([final String prefix = 'test']) =>
    '$prefix-${DateTime.now().millisecondsSinceEpoch}';

/// {@template int_list_builders}
/// Builders for creating integer lists for testing.
/// {@endtemplate}

/// Creates a list of integers with the specified count.
List<int> someInts([final int count = 3, final int start = 1]) =>
    List.generate(count, (final i) => start + i);

/// Creates a single integer.
int anInt([final int value = 42]) => value;
