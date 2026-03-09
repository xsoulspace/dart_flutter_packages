import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;
  final rawPath = '$packageRoot/lib/src/raw/web_speech_recognition_raw.g.dart';
  final dtsPath =
      '$packageRoot/tool/generated/web_speech_recognition.generated.d.ts';

  test('generated raw contains key symbols', () {
    final content = File(rawPath).readAsStringSync();
    expect(
      content,
      contains("external JSFunction? get speechRecognitionConstructor;"),
    );
    expect(
      content,
      contains("external JSFunction? get webkitSpeechRecognitionConstructor;"),
    );
    expect(content, contains('extension type SpeechRecognitionRaw'));
    expect(content, contains('external void start([JSAny? audioTrack]);'));
  });

  test(
    'generator is deterministic across runs',
    () async {
      final beforeRaw = File(rawPath).readAsStringSync();
      final beforeDts = File(dtsPath).readAsStringSync();

      final run1 = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
      ], workingDirectory: packageRoot);
      expect(run1.exitCode, 0, reason: '${run1.stdout}\n${run1.stderr}');

      final run2 = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
      ], workingDirectory: packageRoot);
      expect(run2.exitCode, 0, reason: '${run2.stdout}\n${run2.stderr}');

      final afterRaw = File(rawPath).readAsStringSync();
      final afterDts = File(dtsPath).readAsStringSync();
      expect(afterRaw, equals(beforeRaw));
      expect(afterDts, equals(beforeDts));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'check mode fails on stale generated file and passes after restore',
    () async {
      final file = File(rawPath);
      final original = file.readAsStringSync();

      file.writeAsStringSync('$original\n// stale marker\n');

      final staleCheck = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(staleCheck.exitCode, isNot(0));

      file.writeAsStringSync(original);

      final cleanCheck = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(
        cleanCheck.exitCode,
        0,
        reason: '${cleanCheck.stdout}\n${cleanCheck.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'check mode fails on stale declaration file and passes after restore',
    () async {
      final file = File(dtsPath);
      final original = file.readAsStringSync();

      file.writeAsStringSync('$original\n// stale declaration marker\n');

      final staleCheck = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(staleCheck.exitCode, isNot(0));

      file.writeAsStringSync(original);

      final cleanCheck = await Process.run('dart', <String>[
        'run',
        'tool/generate.dart',
        '--check',
      ], workingDirectory: packageRoot);

      expect(
        cleanCheck.exitCode,
        0,
        reason: '${cleanCheck.stdout}\n${cleanCheck.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
