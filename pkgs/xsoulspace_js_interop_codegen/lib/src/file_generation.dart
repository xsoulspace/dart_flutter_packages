import 'dart:io';

final class GenerationEdits {
  GenerationEdits();

  final List<String> touchedFiles = <String>[];
  final List<String> mismatches = <String>[];

  bool get hasMismatches => mismatches.isNotEmpty;
}

void checkOrWriteGeneratedFile({
  required final String path,
  required final String content,
  required final bool checkOnly,
  required final GenerationEdits edits,
}) {
  final file = File(path);
  if (checkOnly) {
    if (!file.existsSync() || file.readAsStringSync() != content) {
      edits.mismatches.add(path);
    }
    return;
  }

  if (!file.existsSync() || file.readAsStringSync() != content) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    edits.touchedFiles.add(path);
  }
}
