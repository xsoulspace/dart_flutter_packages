import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('duplicate decoded keys refuse in all nested objects', () {
    for (final source in [
      '{"a":1,"a":2}',
      r'{"a":1,"\u0061":null}',
      '{"changes":[{"a":1,"a":2}]}',
    ]) {
      expect(() => decodeJsonWithUniqueKeys(source), throwsFormatException);
    }
  });
  test(
    'unique sibling keys and source text preserve ordinary JSON semantics',
    () {
      expect(
        decodeJsonWithUniqueKeys(
          r'{"a":[{"x":1},{"x":2}],"b":"{\"x\":1,\"x\":2}"}',
        ),
        {
          'a': [
            {'x': 1},
            {'x': 2},
          ],
          'b': '{"x":1,"x":2}',
        },
      );
      expect(decodeJsonWithUniqueKeys('{"a":null}'), {'a': null});
      expect(decodeJsonWithUniqueKeys('[]'), isEmpty);
      expect(decodeJsonWithUniqueKeys('null'), isNull);
    },
  );
  test('malformed JSON stays a format refusal', () {
    for (final source in ['{', '{"a":}', ']', '{"a":1} trailing']) {
      expect(() => decodeJsonWithUniqueKeys(source), throwsFormatException);
    }
  });
}
