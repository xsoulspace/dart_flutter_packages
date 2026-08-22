import 'package:from_json_to_json/from_json_to_json.dart';

part 'foundation_schema_json.dart';

/// Opaque handle returned to Dart after successful materialization.
extension type const GenerationSchemaHandle(String value) {}

class SchemaBundle {
  const SchemaBundle({
    this.root = NullSchema.empty,
    this.dependencies = const [],
  });

  factory SchemaBundle.fromJson(Map<String, dynamic> json) => SchemaBundle(
    root: schemaFromJson(jsonDecodeMapAs(json['root'])),
    dependencies: jsonDecodeListAs<Map<String, dynamic>>(
      json['dependencies'],
    ).map(schemaFromJson).toList(),
  );
  static const empty = SchemaBundle();
  static const string = empty;

  final Schema root;
  final List<Schema> dependencies;

  Map<String, dynamic> toJson() {
    if (isEmpty) return {};
    return {
      'root': schemaToJson(root),
      'dependencies': dependencies.map(schemaToJson).toList(),
    };
  }

  bool get isNotEmpty => !isEmpty;
  bool get isEmpty {
    if (root case NullSchema _ || PrimitiveSchema _ when dependencies.isEmpty) {
      return true;
    }
    return false;
  }
}

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
    required this.choices,
    this.description,
  });

  final String name;
  final String? description;
  final List<Schema> choices;
}

/// Enum of string literals
final class EnumSchema extends Schema {
  const EnumSchema({required this.name, required this.cases, this.description});

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
  static const empty = NullSchema();
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
    required this.schema,
    this.description,
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

final class ConstantTextGuide extends Guide {
  const ConstantTextGuide(this.text);
  final String text;
}

final class RangeGuide<T extends num> extends Guide {
  const RangeGuide(this.min, this.max);
  final T min;
  final T max;
}

final class CountGuide extends Guide {
  const CountGuide(this.count);
  final int count;
}

final class PatternGuide extends Guide {
  const PatternGuide(this.pattern);
  final String pattern;
}
