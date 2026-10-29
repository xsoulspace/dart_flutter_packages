import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  group('slugify', () {
    test('empty and all-punctuation input return the empty string', () {
      expect(slugify(''), '');
      expect(slugify('!!!'), '');
      expect(slugify('   '), '');
    });
    test('case folds and runs collapse to one dash', () {
      expect(slugify('Hello World'), 'hello-world');
      expect(slugify('a__b//c'), 'a-b-c');
      expect(slugify('  multiple   spaces  '), 'multiple-spaces');
    });
    test('digits are preserved and edges are trimmed', () {
      expect(slugify('v242-final'), 'v242-final');
      expect(slugify('--already-a-slug--'), 'already-a-slug');
    });
  });
}
