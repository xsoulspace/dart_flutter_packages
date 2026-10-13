import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  const schema = {
    'type': 'object',
    'properties': {
      'required': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'},
        ],
      },
      'optional': {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'},
        ],
      },
      'items': {
        'type': 'array',
        'items': {'type': 'integer'},
        'minItems': 1,
        'maxItems': 2,
      },
    },
    'required': ['required'],
    'additionalProperties': false,
  };
  bool valid(Object? value) =>
      validateJsonAgainstSchema(value: value, schema: schema).success;

  test(
    'required means present; nullable and optional alternatives retain types',
    () {
      expect(valid({'required': null}), true);
      expect(valid({'required': 'ok'}), true);
      expect(valid({'required': 'ok', 'optional': null}), true);
      expect(valid({'required': 'ok', 'optional': 'allowed'}), true);
      expect(valid({'optional': 'missing required'}), false);
      expect(valid({'required': 'ok', 'optional': 42}), false);
      expect(valid({'required': 42}), false);
    },
  );
  test(
    'closed objects reject extra properties and arrays enforce bounds/items',
    () {
      expect(valid({'required': 'ok', 'undeclared': true}), false);
      expect(
        valid({
          'required': 'ok',
          'items': [1, 2],
        }),
        true,
      );
      expect(valid({'required': 'ok', 'items': []}), false);
      expect(
        valid({
          'required': 'ok',
          'items': [1, 2, 3],
        }),
        false,
      );
      expect(
        valid({
          'required': 'ok',
          'items': ['wrong'],
        }),
        false,
      );
    },
  );
  test('additional property schemas validate each undeclared value', () {
    const open = {
      'type': 'object',
      'additionalProperties': {'type': 'integer'},
    };
    expect(
      validateJsonAgainstSchema(value: {'a': 1}, schema: open).success,
      true,
    );
    expect(
      validateJsonAgainstSchema(value: {'a': 'wrong'}, schema: open).success,
      false,
    );
  });
  test('malformed composition and bounds refuse as schema errors', () {
    for (final invalid in <Map<String, dynamic>>[
      {'anyOf': []},
      {'anyOf': null},
      {'additionalProperties': null},
      {'minItems': null},
      {'maxItems': null},
      {
        'anyOf': ['not a schema'],
      },
      {'additionalProperties': 'not a flag'},
      {'minItems': -1},
      {'maxItems': 1.5},
      {'minItems': 2, 'maxItems': 1},
    ]) {
      expect(
        validateSchemaDefinition(invalid).success,
        false,
        reason: '$invalid',
      );
    }
  });
}
