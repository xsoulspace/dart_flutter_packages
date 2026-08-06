// lib/src/schema_json.dart

import 'foundation_schema.dart';

Map<String, dynamic> schemaToJson(Schema s) {
  return switch (s) {
    ObjectSchema(
      :final name,
      :final description,
      :final properties,
      :final representNilExplicitly,
    ) =>
      {
        'kind': 'object',
        'name': name,
        if (description != null) 'description': description,
        'representNilExplicitly': representNilExplicitly,
        'properties': properties.map(_propertyToJson).toList(),
      },
    AnyOfSchema(:final name, :final description, :final choices) => {
      'kind': 'anyOf',
      'name': name,
      if (description != null) 'description': description,
      'choices': choices.map(schemaToJson).toList(),
    },
    EnumSchema(:final name, :final description, :final cases) => {
      'kind': 'enum',
      'name': name,
      if (description != null) 'description': description,
      'cases': cases,
    },
    ArraySchema(:final item, :final minItems, :final maxItems) => {
      'kind': 'array',
      'item': schemaToJson(item),
      if (minItems != null) 'minItems': minItems,
      if (maxItems != null) 'maxItems': maxItems,
    },
    ReferenceSchema(:final name) => {
      'kind': 'reference',
      'referenceName': name,
    },
    NullSchema() => {'kind': 'null'},
    PrimitiveSchema(:final type, :final guides) => {
      'kind': 'primitive',
      'primitiveType': _primitiveTypeToString(type),
      if (guides.isNotEmpty) 'guides': guides.map(_guideToJson).toList(),
    },
  };
}

Schema schemaFromJson(Map<String, dynamic> json) {
  final kind = json['kind'] as String;

  return switch (kind) {
    'object' => ObjectSchema(
      name: json['name'] as String,
      description: json['description'] as String?,
      representNilExplicitly: json['representNilExplicitly'] as bool? ?? false,
      properties: (json['properties'] as List<dynamic>)
          .map((e) => _propertyFromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    'anyOf' => AnyOfSchema(
      name: json['name'] as String,
      description: json['description'] as String?,
      choices: (json['choices'] as List<dynamic>)
          .map((e) => schemaFromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    'enum' => EnumSchema(
      name: json['name'] as String,
      description: json['description'] as String?,
      cases: (json['cases'] as List<dynamic>).cast<String>(),
    ),
    'array' => ArraySchema(
      item: schemaFromJson(json['item'] as Map<String, dynamic>),
      minItems: json['minItems'] as int?,
      maxItems: json['maxItems'] as int?,
    ),
    'reference' => ReferenceSchema(json['referenceName'] as String),
    'null' => const NullSchema(),
    'primitive' => PrimitiveSchema(
      type: _primitiveTypeFromString(json['primitiveType'] as String),
      guides:
          (json['guides'] as List<dynamic>?)
              ?.map((e) => _guideFromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    ),
    _ => throw ArgumentError('Unknown schema kind: $kind'),
  };
}

// ---------- helpers ----------

Map<String, dynamic> _propertyToJson(SchemaProperty p) => {
  'name': p.name,
  if (p.description != null) 'description': p.description,
  'schema': schemaToJson(p.schema),
  'isOptional': p.isOptional,
};

SchemaProperty _propertyFromJson(Map<String, dynamic> json) => SchemaProperty(
  name: json['name'] as String,
  description: json['description'] as String?,
  schema: schemaFromJson(json['schema'] as Map<String, dynamic>),
  isOptional: json['isOptional'] as bool? ?? false,
);

String _primitiveTypeToString(PrimitiveType t) => switch (t) {
  PrimitiveType.string => 'String',
  PrimitiveType.int => 'Int',
  PrimitiveType.double => 'Double',
  PrimitiveType.bool => 'Bool',
};

PrimitiveType _primitiveTypeFromString(String s) => switch (s) {
  'String' => PrimitiveType.string,
  'Int' => PrimitiveType.int,
  'Double' => PrimitiveType.double,
  'Bool' => PrimitiveType.bool,
  _ => throw ArgumentError('Unknown primitive type: $s'),
};

Map<String, dynamic> _guideToJson(Guide g) => switch (g) {
  DescriptionGuide(:final text) => {'kind': 'description', 'text': text},
  RangeGuide(:final min, :final max) => {
    'kind': 'range',
    'min': min,
    'max': max,
  },
  CountGuide(:final count) => {'kind': 'count', 'count': count},
  PatternGuide(:final pattern) => {'kind': 'pattern', 'pattern': pattern},
};

Guide _guideFromJson(Map<String, dynamic> json) {
  final kind = json['kind'] as String;
  return switch (kind) {
    'description' => DescriptionGuide(json['text'] as String),
    'range' => RangeGuide((json['min'] as num), (json['max'] as num)),
    'count' => CountGuide(json['count'] as int),
    'pattern' => PatternGuide(json['pattern'] as String),
    _ => throw ArgumentError('Unknown guide kind: $kind'),
  };
}
