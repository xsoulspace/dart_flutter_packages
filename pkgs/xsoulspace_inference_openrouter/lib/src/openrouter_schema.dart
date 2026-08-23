// ignore_for_file: lines_longer_than_80_chars

/// Maps core `SchemaBundle` trees to standard JSON Schema for OpenRouter's
/// `response_format: {"type": "json_schema"}` structured outputs.
///
/// The core format (`foundation_schema_json.dart`) is backend-neutral and
/// kind-tagged; each backend materializes it natively (AFM via
/// GenerationSchema) or converts it. This is the OpenRouter conversion.
///
/// Conversion notes:
/// - Objects get `additionalProperties: false` and every property listed in
///   `required` — OpenRouter's strict mode rejects schemas without both.
/// - Optional properties are still listed as required but typed to allow
///   null via anyOf with `{"type": "null"}` where representNilExplicitly is
///   set; free-tier models handle plain-required more reliably, so optionality
///   degrades to required-with-null.
library;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Convert a [SchemaBundle] root to a JSON-Schema object.
Map<String, dynamic> bundleToJsonSchema(SchemaBundle bundle) =>
    schemaToJsonSchema(bundle.root);

/// Convert a single [Schema] node.
Map<String, dynamic> schemaToJsonSchema(Schema schema) => switch (schema) {
  final ObjectSchema o => () {
    final properties = <String, dynamic>{};
    final required = <String>[];
    for (final p in o.properties) {
      var propSchema = schemaToJsonSchema(p.schema);
      // Optional properties stay out of `required` but are typed to allow
      // null so strict mode accepts their absence.
      if (p.isOptional && p.schema is! NullSchema) {
        propSchema = {
          'anyOf': [
            propSchema,
            {'type': 'null'},
          ],
        };
      }
      properties[p.name] = {
        if (p.description != null) 'description': p.description,
        ...propSchema,
      };
      if (!p.isOptional) required.add(p.name);
    }
    return {
      'type': 'object',
      if (o.description != null) 'description': o.description,
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    };
  }(),
  final AnyOfSchema a => () {
    final anyOf = a.choices.map(schemaToJsonSchema).toList();
    // A single-choice anyOf collapses; otherwise pass through.
    return anyOf.length == 1 ? anyOf.first : {'anyOf': anyOf};
  }(),
  final EnumSchema e => {
    'type': 'string',
    if (e.description != null) 'description': e.description,
    'enum': e.cases,
  },
  final ArraySchema arr => {
    'type': 'array',
    'items': schemaToJsonSchema(arr.item),
    if (arr.minItems != null) 'minItems': arr.minItems,
    if (arr.maxItems != null) 'maxItems': arr.maxItems,
  },
  final ReferenceSchema r => throw ArgumentError(
    'Unresolved schema reference "${r.name}" — resolve references '
    'before converting (dependencies must be inlined).',
  ),
  NullSchema() => {'type': 'null'},
  final PrimitiveSchema p => () {
    final type = switch (p.type) {
      PrimitiveType.string => 'string',
      PrimitiveType.double => 'number',
      PrimitiveType.int => 'integer',
      PrimitiveType.bool => 'boolean',
    };
    return {'type': type};
  }(),
};
