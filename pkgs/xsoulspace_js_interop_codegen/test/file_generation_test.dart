import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

void main() {
  test('checkOrWriteGeneratedFile writes and checks deterministically', () {
    final dir = Directory.systemTemp.createTempSync('codegen_file_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final path = '${dir.path}/out.txt';
    final edits = GenerationEdits();

    checkOrWriteGeneratedFile(
      path: path,
      content: 'abc\n',
      checkOnly: false,
      edits: edits,
    );
    expect(File(path).readAsStringSync(), 'abc\n');
    expect(edits.touchedFiles, hasLength(1));

    final checkEdits = GenerationEdits();
    checkOrWriteGeneratedFile(
      path: path,
      content: 'abc\n',
      checkOnly: true,
      edits: checkEdits,
    );
    expect(checkEdits.mismatches, isEmpty);

    final staleCheck = GenerationEdits();
    checkOrWriteGeneratedFile(
      path: path,
      content: 'changed\n',
      checkOnly: true,
      edits: staleCheck,
    );
    expect(staleCheck.mismatches, hasLength(1));
  });
}
