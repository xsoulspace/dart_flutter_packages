import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

import '../tool/native_cli_bundle.dart';

void main() {
  late Directory root;
  late Directory profile;
  late Directory bundle;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native_closure_test_');
    profile = Directory('${root.path}/profile')..createSync();
    bundle = Directory('${root.path}/bundle')..createSync();
    File('${bundle.path}/lib/libmlx_native.dylib')
      ..createSync(recursive: true)
      ..writeAsStringSync('current-image');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<void> producer(String label, String image, String metal) async {
    final folder = Directory(
      '${profile.path}/hooks_runner/'
      'xsoulspace_inference_mlx_native/$label',
    )..createSync(recursive: true);
    final dylib = File('${folder.path}/libmlx_native.dylib')
      ..writeAsStringSync(image);
    File('${folder.path}/mlx.metallib').writeAsStringSync(metal);
    await File('${folder.path}/output.json').writeAsString(
      jsonEncode({
        'assets': [
          {
            'encoding': {
              'id': 'package:xsoulspace_inference_mlx_native/mlx_native',
              'file': dylib.path,
            },
          },
        ],
      }),
    );
  }

  test(
    'packages only the exact image producer Metal and keeps receipt',
    () async {
      await producer('old', 'old-image', 'old-metal');
      await producer('current', 'current-image', 'current-metal');
      final receipt = await completeNativeCliBundle(
        profile: profile,
        bundle: bundle,
      );
      expect(
        File('${bundle.path}/lib/mlx.metallib').readAsStringSync(),
        'current-metal',
      );
      expect(receipt['producerOutput'], contains('/current/'));
      expect(File('${bundle.path}/native_closure.json').existsSync(), isTrue);
    },
  );
  test('refuses unknown native image without guessing cache assets', () async {
    await producer('old', 'old-image', 'old-metal');
    await expectLater(
      completeNativeCliBundle(profile: profile, bundle: bundle),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'code',
          contains('native_bundle_producer_unmatched'),
        ),
      ),
    );
    expect(File('${bundle.path}/lib/mlx.metallib').existsSync(), isFalse);
  });
  test('refuses equal image with conflicting producer Metal', () async {
    await producer('a', 'current-image', 'a-metal');
    await producer('b', 'current-image', 'b-metal');
    await expectLater(
      completeNativeCliBundle(profile: profile, bundle: bundle),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'code',
          contains('native_bundle_producer_ambiguous'),
        ),
      ),
    );
  });
  test('matches complete SDK-relocated Mach-O bytes to its producer', () async {
    if (!Platform.isMacOS) return markTestSkipped('macOS relocation control');
    await producer('native', 'placeholder', 'native-metal');
    final folder = Directory(
      '${profile.path}/hooks_runner/'
      'xsoulspace_inference_mlx_native/native',
    );
    final source = File('${folder.path}/probe.c')
      ..writeAsStringSync('int closure_probe(void) { return 7; }\n');
    final image = File('${folder.path}/libmlx_native.dylib');
    final target = File('${bundle.path}/lib/libmlx_native.dylib');
    final compile = await runBounded('/usr/bin/clang', [
      '-dynamiclib',
      source.path,
      '-o',
      image.path,
    ], deadline: const Duration(seconds: 30));
    expect(compile.ok, isTrue, reason: compile.stderr);
    await image.copy(target.path);
    for (final command in [
      [
        '/usr/bin/install_name_tool',
        '-id',
        '@rpath/lib/libmlx_native.dylib',
        target.path,
      ],
      ['/usr/bin/codesign', '--force', '--sign', '-', target.path],
    ]) {
      final result = await runBounded(
        command.first,
        command.sublist(1),
        deadline: const Duration(seconds: 30),
      );
      expect(result.ok, isTrue, reason: result.stderr);
    }
    final receipt = await completeNativeCliBundle(
      profile: profile,
      bundle: bundle,
    );
    expect(receipt['sdkRelocation'], 'macos-cli-id-and-adhoc-sign-v1');
    expect(receipt['producerImageSha256'], isNot(receipt['nativeImageSha256']));
    expect(
      File('${bundle.path}/lib/mlx.metallib').readAsStringSync(),
      'native-metal',
    );
  });
}
