import 'foundation_schema.dart';

/// short from Foundation Models
///
/// ```dart
// ignore: lines_longer_than_80_chars
/// final npcSchema = FM.object('Npc', description: 'A character that can order coffee', properties: () => [
///   FM.prop('name', FM.string(guides: [DescriptionGuide('A full name')])),
///   FM.prop('level', FM.integer(guides: [RangeGuide(1, 10)])),
///   FM.prop('attributes', FM.array(ref('Attribute'), min: 3, max: 3)),
///   FM.prop('encounter', FM.ref('Encounter')),
/// ]);
///
/// final attributeSchema = FM.enum_('Attribute', ['sassy', 'tired', 'hungry']);
///
/// final encounterSchema = FM.anyOf('Encounter', [
///   FM.object('OrderCoffee', properties: () => [
///     FM.prop('drink', string()),
///   ]),
///   FM.object('WantToTalkToManager', properties: () => [
///     FM.prop('complaint', string()),
///   ]),
/// ]);
///
/// // Root + dependencies
/// final root = npcSchema;
/// final dependencies = [attributeSchema, encounterSchema];
/// ````
// ignore: avoid_classes_with_only_static_members
class FM {
  static Schema object(
    String name, {
    required List<SchemaProperty> Function() properties,
    String? description,
    bool representNilExplicitly = false,
  }) => ObjectSchema(
    name: name,
    description: description,
    representNilExplicitly: representNilExplicitly,
    properties: properties(),
  );

  static SchemaProperty prop(
    String name,
    Schema schema, {
    String? description,
    bool optional = false,
  }) => SchemaProperty(
    name: name,
    description: description,
    schema: schema,
    isOptional: optional,
  );

  static Schema string({List<Guide> guides = const []}) =>
      PrimitiveSchema(type: PrimitiveType.string, guides: guides);

  static Schema double({List<Guide> guides = const []}) =>
      PrimitiveSchema(type: PrimitiveType.double, guides: guides);

  static Schema integer({List<Guide> guides = const []}) =>
      PrimitiveSchema(type: PrimitiveType.int, guides: guides);

  // ... same for double, bool

  static Schema array(Schema item, {int? min, int? max}) =>
      ArraySchema(item: item, minItems: min, maxItems: max);

  static Schema anyOf(
    String name,
    List<Schema> choices, {
    String? description,
  }) => AnyOfSchema(name: name, description: description, choices: choices);

  static Schema enum_(String name, List<String> cases, {String? description}) =>
      EnumSchema(name: name, description: description, cases: cases);

  static Schema ref(String name) => ReferenceSchema(name);

  static Schema get nullSchema => NullSchema.empty;
}
