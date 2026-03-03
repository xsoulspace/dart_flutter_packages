import 'dart:io';

import 'package:path/path.dart' as p;

const _generatedRaw = '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: CloudKit JS declaration snapshot (tool/generated/cloudkit.generated.d.ts)

@JS()
library;

import 'dart:js_interop';

@JS('CloudKit')
external JSAny? get cloudKitGlobal;

bool get hasCloudKitGlobal => cloudKitGlobal != null;
''';

Future<void> main(final List<String> args) async {
  final checkOnly = args.contains('--check');
  final packageRoot = Directory.current.path;
  final rawPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'cloudkit_raw.g.dart',
  );
  final dtsPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'cloudkit.generated.d.ts',
  );

  final dtsFile = File(dtsPath);
  if (!dtsFile.existsSync()) {
    stderr.writeln('Missing CloudKit d.ts snapshot: $dtsPath');
    exitCode = 2;
    return;
  }

  final rawFile = File(rawPath);
  if (checkOnly) {
    final current = rawFile.existsSync() ? rawFile.readAsStringSync() : '';
    if (current != _generatedRaw) {
      stderr.writeln('Generated raw bindings are out of date.');
      stderr.writeln('Run: dart run tool/generate.dart');
      exitCode = 1;
    }
    return;
  }

  await rawFile.writeAsString(_generatedRaw);
  stdout.writeln('Generated $rawPath');
}
