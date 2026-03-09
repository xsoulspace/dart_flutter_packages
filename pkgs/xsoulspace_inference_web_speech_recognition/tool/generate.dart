import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

Future<void> main(final List<String> args) async {
  final checkOnly = _parseCheckOnly(args);
  if (checkOnly == null) {
    exitCode = 2;
    return;
  }

  final packageRoot = Directory.current.path;
  final dtsPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'web_speech_recognition.generated.d.ts',
  );
  final rawPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'web_speech_recognition_raw.g.dart',
  );
  final snapshotPath = p.join(packageRoot, 'tool', 'api_snapshot.json');
  final diffPath = p.join(packageRoot, 'tool', 'api_diff.json');

  final dtsFile = File(dtsPath);
  if (!dtsFile.existsSync()) {
    stderr.writeln('Missing Web Speech d.ts snapshot: $dtsPath');
    exitCode = 2;
    return;
  }

  final dtsContent = dtsFile.readAsStringSync();

  final parser = TypeScriptIrParser.fromSharedCore(
    currentPackageRoot: packageRoot,
  );
  await parser.ensureDependencies();

  final ir = await parser.parseFileToIr(dtsPath);
  final rawCode = emitRawCode();

  final parserSymbols = (ir['symbols'] as List<dynamic>? ?? <dynamic>[])
      .cast<String>();
  final symbols = _extractSymbols(
    dtsContent: dtsContent,
    parserSymbols: parserSymbols,
  );

  final irGlobalSymbols =
      (ir['globalDeclarations'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, Object?>>()
          .where((final value) => value['kind'] == 'variable')
          .map((final value) => value['name'] as String?)
          .whereType<String>();
  final globalSymbols = _extractGlobalSymbols(
    dtsContent: dtsContent,
    parserGlobalSymbols: irGlobalSymbols,
  );

  final sourceHash = sha256Hex(utf8.encode(dtsContent));
  final snapshot = <String, Object?>{
    'source': 'tool/generated/web_speech_recognition.generated.d.ts',
    'sourceHash': sourceHash,
    'generated': 'lib/src/raw/web_speech_recognition_raw.g.dart',
    'symbolCount': symbols.length,
    'symbols': symbols,
    'globalSymbols': globalSymbols,
  };

  final snapshotFile = File(snapshotPath);
  final oldSnapshot = snapshotFile.existsSync()
      ? jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>
      : <String, Object?>{'symbols': <Object?>[]};

  final oldSymbols = (oldSnapshot['symbols'] as List<dynamic>? ?? <dynamic>[])
      .cast<String>()
      .toSet();
  final newSymbols = symbols.toSet();

  final diff = <String, Object?>{
    'source': snapshot['source'],
    ...buildApiDiff(
      fromVersion: oldSnapshot['sourceHash'],
      toVersion: sourceHash,
      oldSymbols: oldSymbols,
      newSymbols: newSymbols,
      fromVersionField: 'fromSourceHash',
      toVersionField: 'toSourceHash',
    ),
  };

  final edits = GenerationEdits();
  checkOrWriteGeneratedFile(
    path: rawPath,
    content: rawCode,
    checkOnly: checkOnly,
    edits: edits,
  );
  checkOrWriteGeneratedFile(
    path: snapshotPath,
    content: '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
    checkOnly: checkOnly,
    edits: edits,
  );
  checkOrWriteGeneratedFile(
    path: diffPath,
    content: '${const JsonEncoder.withIndent('  ').convert(diff)}\n',
    checkOnly: checkOnly,
    edits: edits,
  );

  if (edits.hasMismatches) {
    stderr.writeln('Generated files are out of date:');
    for (final mismatch in edits.mismatches) {
      stderr.writeln(' - ${p.relative(mismatch, from: packageRoot)}');
    }
    stderr.writeln('Run: dart run tool/generate.dart');
    exitCode = 1;
    return;
  }

  if (!checkOnly) {
    stdout.writeln('Generated files:');
    for (final path in edits.touchedFiles) {
      stdout.writeln(' - ${p.relative(path, from: packageRoot)}');
    }
  }
}

bool? _parseCheckOnly(final List<String> args) {
  var checkOnly = false;
  for (final arg in args) {
    if (arg == '--check') {
      checkOnly = true;
      continue;
    }
    if (arg == '--help') {
      stdout.writeln('Usage: dart run tool/generate.dart [--check]');
      return null;
    }
    stderr.writeln('Unknown option: $arg');
    return null;
  }
  return checkOnly;
}

String emitRawCode() {
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: Web Speech API declaration snapshot
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('SpeechRecognition')
external JSFunction? get speechRecognitionConstructor;

@JS('webkitSpeechRecognition')
external JSFunction? get webkitSpeechRecognitionConstructor;

extension type SpeechRecognitionAlternativeRaw(JSObject _) implements JSObject {
  external JSString get transcript;
  external JSNumber get confidence;
}

extension type SpeechRecognitionResultRaw(JSObject _) implements JSObject {
  external JSBoolean get isFinal;
  external JSNumber get length;
  external SpeechRecognitionAlternativeRaw item(JSNumber index);
}

extension type SpeechRecognitionResultListRaw(JSObject _) implements JSObject {
  external JSNumber get length;
  external SpeechRecognitionResultRaw item(JSNumber index);
}

extension type SpeechRecognitionEventRaw(JSObject _) implements JSObject {
  external JSNumber get resultIndex;
  external SpeechRecognitionResultListRaw get results;
}

extension type SpeechRecognitionErrorEventRaw(JSObject _) implements JSObject {
  external JSString get error;
  external JSString? get message;
}

extension type SpeechRecognitionRaw(JSObject _) implements JSObject {
  external JSBoolean get continuous;
  external set continuous(JSBoolean value);

  external JSBoolean get interimResults;
  external set interimResults(JSBoolean value);

  external JSString get lang;
  external set lang(JSString value);

  external JSNumber get maxAlternatives;
  external set maxAlternatives(JSNumber value);

  external JSFunction? get onresult;
  external set onresult(JSFunction? value);

  external JSFunction? get onerror;
  external set onerror(JSFunction? value);

  external JSFunction? get onend;
  external set onend(JSFunction? value);

  external void start([JSAny? audioTrack]);
  external void stop();
  external void abort();
}
''';
}

List<String> _extractSymbols({
  required final String dtsContent,
  required final List<String> parserSymbols,
}) {
  final symbols = <String>{...parserSymbols};
  final regex = RegExp(
    r'^(?:export\s+)?(?:declare\s+)?(?:interface|type|enum|class|const|function)\s+([A-Za-z_][A-Za-z0-9_]*)',
    multiLine: true,
  );
  for (final match in regex.allMatches(dtsContent)) {
    final symbol = match.group(1);
    if (symbol != null && symbol.isNotEmpty) {
      symbols.add(symbol);
    }
  }
  final sorted = symbols.toList()..sort();
  return sorted;
}

List<String> _extractGlobalSymbols({
  required final String dtsContent,
  required final Iterable<String> parserGlobalSymbols,
}) {
  final symbols = <String>{...parserGlobalSymbols};
  final regex = RegExp(
    r'^\s*declare\s+var\s+([A-Za-z_][A-Za-z0-9_]*)',
    multiLine: true,
  );
  for (final match in regex.allMatches(dtsContent)) {
    final symbol = match.group(1);
    if (symbol != null && symbol.isNotEmpty) {
      symbols.add(symbol);
    }
  }
  final sorted = symbols.toList()..sort();
  return sorted;
}
