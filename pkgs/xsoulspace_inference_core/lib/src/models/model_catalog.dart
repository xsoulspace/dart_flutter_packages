
/// Any ML model.
///
/// [tier] ranks models for escalation: higher tier = stronger model.
/// Escalation always moves to a strictly higher tier; models of equal or
/// unknown tier are never chosen.
class Model {
  const Model({
    this.id = ModelId.empty,
    this.name = DefaultModelNames.appleFoundation,
    this.tier = 0,
    this.maxInFlight = 1,
  });
  static const empty = Model();
  final ModelId id;
  final ModelName name;

  /// Escalation rank. 0 = default/local, higher = stronger.
  final int tier;

  /// How many generation requests the backend can run concurrently for
  /// this model. Declared by the backend's client (e.g. Apple Foundation
  /// Models serializes requests on-device -> 1; hosted APIs typically >= 8).
  final int maxInFlight;
}

/// Marker contract for provider model-name enums.
///
/// Prefer a definitive enumeration:
/// ```dart
/// enum ModelNames implements ModelName {
/// ```
abstract class ModelName implements Enum {}

enum DefaultModelNames implements ModelName { appleFoundation }

/// Stable identifier for a [Model] within a router catalog.
extension type const ModelId(String value) {
  factory ModelId.create() => ModelId(_nextUnique('model'));
  static const empty = ModelId('');
}

int _modelIdCounter = 0;
String _nextUnique(String prefix) {
  final count = _modelIdCounter++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$count';
}
