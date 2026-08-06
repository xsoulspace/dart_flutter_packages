import 'package:xsoulspace_inference_apple_foundation/src/dynamic_scheme/schema_bundle.dart';

///```dart
/// final schemaTree = SchemaBundle(
///   root: npcSchema,
///   dependencies: [attributeSchema, encounterSchema],
/// );
///
/// // Send to Swift (FFI, method channel, or isolate bridge)
/// await FoundationSchema.materialize(schemaTree);
///```
/// Root of every schema definition.
sealed class Schema {
  const Schema();
}

/// Object / product type
final class ObjectSchema extends Schema {
  const ObjectSchema({
    required this.name,
    this.description,
    this.properties = const [],
    this.representNilExplicitly = false,
  });

  final String name;
  final String? description;
  final List<SchemaProperty> properties;
  final bool representNilExplicitly;
}

/// Sum type
final class AnyOfSchema extends Schema {
  const AnyOfSchema({
    required this.name,
    this.description,
    required this.choices,
  });

  final String name;
  final String? description;
  final List<Schema> choices;
}

/// Enum of string literals
final class EnumSchema extends Schema {
  const EnumSchema({required this.name, this.description, required this.cases});

  final String name;
  final String? description;
  final List<String> cases;
}

/// Array
final class ArraySchema extends Schema {
  const ArraySchema({required this.item, this.minItems, this.maxItems});

  final Schema item;
  final int? minItems;
  final int? maxItems;
}

/// Reference to another named schema (for recursive / shared types)
final class ReferenceSchema extends Schema {
  const ReferenceSchema(this.name);
  final String name;
}

/// Null
final class NullSchema extends Schema {
  const NullSchema();
}

/// Primitive (backed by Swift `DynamicGenerationSchema(type:guides:)`)
final class PrimitiveSchema extends Schema {
  const PrimitiveSchema({required this.type, this.guides = const []});

  final PrimitiveType type;
  final List<Guide> guides;
}

enum PrimitiveType { string, int, double, bool }

/// Property of an object
final class SchemaProperty {
  const SchemaProperty({
    required this.name,
    this.description,
    required this.schema,
    this.isOptional = false,
  });

  final String name;
  final String? description;
  final Schema schema;
  final bool isOptional;
}

/// Guides (map 1:1 to GenerationGuide)
sealed class Guide {
  const Guide();
}

final class DescriptionGuide extends Guide {
  const DescriptionGuide(this.text);
  final String text;
}

final class RangeGuide extends Guide {
  const RangeGuide(this.min, this.max);
  final num min;
  final num max;
}

final class CountGuide extends Guide {
  const CountGuide(this.count);
  final int count;
}

final class PatternGuide extends Guide {
  const PatternGuide(this.pattern);
  final String pattern;
}

class FoundationSchema {
  /// Serializes the bundle and asks the native side to materialize
  /// a real GenerationSchema.
  ///
  /// Returns an opaque handle / id that can later be used with the
  /// LanguageModelSession on the Swift side, or throws on failure.
  static Future<GenerationSchemaHandle> materialize(SchemaBundle bundle) async {
    final json = bundle.toJson();

    // Transport – replace with your real bridge (FFI, method channel, etc.)
    final result = await _nativeMaterialize(json);

    return GenerationSchemaHandle(result['id'] as String);
  }

  // Placeholder for the actual platform channel / FFI call
  static Future<Map<String, dynamic>> _nativeMaterialize(
    Map<String, dynamic> json,
  ) {
    // Example with method channel:
    // return _channel.invokeMapMethod('materializeSchema', json);
    throw UnimplementedError('Wire this to your Swift bridge');
  }
}

/// Opaque handle returned to Dart after successful materialization.
class GenerationSchemaHandle {
  const GenerationSchemaHandle(this.id);
  final String id;
}
