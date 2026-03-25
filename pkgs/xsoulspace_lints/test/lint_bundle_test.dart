import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('lint bundle files', () {
    test('includes all published rule entrypoints', () {
      expect(File('lib/app.yaml').existsSync(), isTrue);
      expect(File('lib/library.yaml').existsSync(), isTrue);
      expect(File('lib/public_library.yaml').existsSync(), isTrue);
    });

    test('app.yaml keeps strict base include and key lint rules', () {
      final appYaml = File('lib/app.yaml').readAsStringSync();

      expect(appYaml, contains('include: package:lints/recommended.yaml'));
      expect(appYaml, contains('avoid_print: true'));
      expect(appYaml, contains('discarded_futures: true'));
    });

    test('public library profile enforces API docs', () {
      final publicLibrary = File('lib/public_library.yaml').readAsStringSync();

      expect(publicLibrary, contains('include: library.yaml'));
      expect(publicLibrary, contains('public_member_api_docs: true'));
    });
  });
}
