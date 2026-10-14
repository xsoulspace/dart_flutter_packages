import 'package:meta/meta.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Base of declarative post-condition checks evaluated against one
/// [Snapshot].
///
/// Checks are pure predicates over the semantic tree (plus the URL when
/// the transport exposes one); they never mutate anything. A failed check
/// is a failed step — there is no soft verify.
sealed class VerifyCheck {
  /// Creates a check.
  const VerifyCheck();

  /// Restores a check from its plan-document shape (the decoded YAML/JSON
  /// map must carry exactly one check key).
  factory VerifyCheck.fromJson(Object? json) {
    if (json is! Map<Object?, Object?> || json.isEmpty) {
      throw const FormatException(
        'a check must be a non-empty map with exactly one check key',
      );
    }
    if (json.length != 1) {
      throw FormatException(
        'a check must carry exactly one check key (got '
        '${json.keys.map((key) => key.toString()).join(', ')})',
      );
    }
    final entry = json.entries.single;
    final body = entry.value;
    switch (entry.key) {
      case 'exists':
        return ExistsCheck._locatorJson(body);
      case 'absent':
        return AbsentCheck._locatorJson(body);
      case 'value':
        return ValueCheck.fromJson(body);
      case 'urlContains':
        if (body is! String || body.isEmpty) {
          throw const FormatException('urlContains needs a non-empty string');
        }
        return UrlContainsCheck(body);
      default:
        throw FormatException('unknown check "${entry.key}"');
    }
  }

  /// Evaluates the predicate; `null` means it holds, otherwise a
  /// human-readable reason why it does not.
  String? evaluate(Snapshot snapshot, {Uri? url});

  /// Canonical plan-document shape.
  Map<String, Object?> toJson();
}

/// The locator half of `exists` / `absent` / `value` checks: role and/or
/// accessible name.
@immutable
class CheckLocator {
  /// Creates a locator; at least one field must be set.
  const CheckLocator({this.role, this.name, this.nameContains})
    : assert(
        role != null || name != null || nameContains != null,
        'a check locator needs a role, a name, or nameContains',
      );

  /// Restores a locator from its plan shape (a map of optional
  /// `role` / `name` / `nameContains` strings).
  factory CheckLocator.fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw const FormatException('a locator must be a map');
    }
    String? read(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty) {
        throw FormatException('$key must be a non-empty string');
      }
      return value;
    }

    return CheckLocator(
      role: read('role'),
      name: read('name'),
      nameContains: read('nameContains'),
    );
  }

  /// Exact semantic role to match, when set.
  final String? role;

  /// Exact accessible name to match, when set.
  final String? name;

  /// Accessible-name substring to match, when set.
  final String? nameContains;

  /// Whether [node] satisfies this locator.
  bool matches(AxNode node) {
    final nameNeedle = nameContains;
    if (role != null && node.role != role) return false;
    if (name != null && node.name != name) return false;
    if (nameNeedle != null && !(node.name ?? '').contains(nameNeedle)) {
      return false;
    }
    return true;
  }

  /// Human-readable form for failure reasons.
  String describe() {
    final parts = [
      if (role != null) 'role=$role',
      if (name != null) 'name=$name',
      if (nameContains != null) 'name~=$nameContains',
    ];
    return parts.join('&');
  }

  /// Canonical plan shape.
  Map<String, Object?> toJson() => {
    if (role != null) 'role': role,
    if (name != null) 'name': name,
    if (nameContains != null) 'nameContains': nameContains,
  };
}

/// At least one node matching the locator exists in the snapshot.
class ExistsCheck extends VerifyCheck {
  /// Creates an exists-check.
  ExistsCheck({required this.locator});

  factory ExistsCheck._locatorJson(Object? json) =>
      ExistsCheck(locator: CheckLocator.fromJson(json));

  /// The locator to look for.
  final CheckLocator locator;

  @override
  String? evaluate(Snapshot snapshot, {Uri? url}) =>
      snapshot.nodes.any(locator.matches)
      ? null
      : 'no node matching ${locator.describe()} exists';

  @override
  Map<String, Object?> toJson() => {'exists': locator.toJson()};
}

/// No node matching the locator exists in the snapshot.
class AbsentCheck extends VerifyCheck {
  /// Creates an absent-check.
  AbsentCheck({required this.locator});

  factory AbsentCheck._locatorJson(Object? json) =>
      AbsentCheck(locator: CheckLocator.fromJson(json));

  /// The locator that must not match anything.
  final CheckLocator locator;

  @override
  String? evaluate(Snapshot snapshot, {Uri? url}) {
    final count = snapshot.nodes.where(locator.matches).length;
    return count == 0 ? null : '${locator.describe()} still present x$count';
  }

  @override
  Map<String, Object?> toJson() => {'absent': locator.toJson()};
}

/// A node matching the locator carries a value satisfying the declared
/// equality/containment.
class ValueCheck extends VerifyCheck {
  /// Creates a value-check; at least one comparator must be set.
  ValueCheck({required this.locator, this.equals, this.contains})
    : assert(equals != null || contains != null, 'needs equals or contains');

  /// Restores a value-check from its plan shape.
  factory ValueCheck.fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw const FormatException('a value check must be a map');
    }
    String? read(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String) {
        throw FormatException('$key must be a string');
      }
      return value;
    }

    final equals = read('equals');
    final contains = read('contains');
    if (equals == null && contains == null) {
      throw const FormatException('a value check needs equals or contains');
    }
    return ValueCheck(
      locator: CheckLocator.fromJson(json['locator']),
      equals: equals,
      contains: contains,
    );
  }

  /// Which node's value to read.
  final CheckLocator locator;

  /// The value must equal this string, when set.
  final String? equals;

  /// The value must contain this string, when set.
  final String? contains;

  @override
  String? evaluate(Snapshot snapshot, {Uri? url}) {
    final containsNeedle = contains;
    for (final node in snapshot.nodes) {
      if (!locator.matches(node)) continue;
      final value = node.value ?? '';
      if (equals != null && value != equals) {
        return 'value of ${locator.describe()} was "$value", '
            'expected "$equals"';
      }
      if (containsNeedle != null && !value.contains(containsNeedle)) {
        return 'value of ${locator.describe()} was "$value", '
            'expected to contain "$containsNeedle"';
      }
      return null;
    }
    return 'no node matching ${locator.describe()} exists';
  }

  @override
  Map<String, Object?> toJson() => {
    'value': {
      'locator': locator.toJson(),
      if (equals != null) 'equals': equals,
      if (contains != null) 'contains': contains,
    },
  };
}

/// The surface URL (when the transport exposes one) contains the
/// fragment.
class UrlContainsCheck extends VerifyCheck {
  /// Creates a URL check.
  const UrlContainsCheck(this.fragment);

  /// The substring the URL must contain.
  final String fragment;

  @override
  String? evaluate(Snapshot snapshot, {Uri? url}) {
    if (url == null) {
      return 'urlContains is not supported by this transport';
    }
    return url.toString().contains(fragment)
        ? null
        : 'url "$url" does not contain "$fragment"';
  }

  @override
  Map<String, Object?> toJson() => {'urlContains': fragment};
}
