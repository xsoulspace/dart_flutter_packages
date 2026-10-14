import 'automation_exceptions.dart';

/// Base class for fail-closed, typed composition specs.
///
/// The family validates compositions **before anything runs** (oka
/// pipeline discipline): `validate()` collects every violation as strings,
/// `ensureValid()` throws [SpecViolationException] with all of them at
/// once. Specs are values; validation is pure.
abstract base class TypedSpec {
  /// Creates a spec.
  const TypedSpec();

  /// Collects every violation; an empty list means valid.
  List<String> validate();

  /// Throws [SpecViolationException] when [validate] found violations.
  void ensureValid() {
    final violations = validate();
    if (violations.isNotEmpty) throw SpecViolationException(violations);
  }
}
