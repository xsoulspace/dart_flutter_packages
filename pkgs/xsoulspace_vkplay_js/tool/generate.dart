import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

final class UpstreamLock {
  const UpstreamLock({
    required this.sdkUrl,
    required this.sdkSha512,
    required this.sdkVersion,
    required this.docsUrls,
    required this.docsHash,
    required this.declarationHash,
  });

  final String sdkUrl;
  final String sdkSha512;
  final String sdkVersion;
  final List<String> docsUrls;
  final String docsHash;
  final String declarationHash;

  UpstreamLock copyWith({
    final String? sdkUrl,
    final String? sdkSha512,
    final String? sdkVersion,
    final List<String>? docsUrls,
    final String? docsHash,
    final String? declarationHash,
  }) {
    return UpstreamLock(
      sdkUrl: sdkUrl ?? this.sdkUrl,
      sdkSha512: sdkSha512 ?? this.sdkSha512,
      sdkVersion: sdkVersion ?? this.sdkVersion,
      docsUrls: docsUrls ?? this.docsUrls,
      docsHash: docsHash ?? this.docsHash,
      declarationHash: declarationHash ?? this.declarationHash,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sdkUrl': sdkUrl,
    'sdkSha512': sdkSha512,
    'sdkVersion': sdkVersion,
    'docsUrls': docsUrls,
    'docsHash': docsHash,
    'declarationHash': declarationHash,
  };

  static UpstreamLock fromJson(final Map<String, Object?> json) {
    return UpstreamLock(
      sdkUrl: json['sdkUrl']! as String,
      sdkSha512: json['sdkSha512']! as String,
      sdkVersion: json['sdkVersion']! as String,
      docsUrls: (json['docsUrls']! as List<dynamic>).cast<String>(),
      docsHash: json['docsHash']! as String,
      declarationHash: json['declarationHash']! as String,
    );
  }
}

final class GenerateOptions {
  const GenerateOptions({required this.checkOnly, required this.bump});

  final bool checkOnly;
  final bool bump;
}

Future<void> main(final List<String> args) async {
  final options = _parseOptions(args);
  if (options == null) {
    exitCode = 2;
    return;
  }

  if (options.checkOnly && options.bump) {
    stderr.writeln('--check and --bump cannot be used together.');
    exitCode = 2;
    return;
  }

  final packageRoot = Directory.current.path;
  final lockPath = p.join(packageRoot, 'tool', 'upstream_lock.json');
  final dtsOutputPath = p.join(
    packageRoot,
    'tool',
    'generated',
    'vkplay_sdk.generated.d.ts',
  );
  final rawOutputPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'vkplay_raw.g.dart',
  );
  final snapshotPath = p.join(packageRoot, 'tool', 'api_snapshot.json');
  final diffPath = p.join(packageRoot, 'tool', 'api_diff.json');

  final lockFile = File(lockPath);
  if (!lockFile.existsSync()) {
    stderr.writeln('Missing lock file: $lockPath');
    exitCode = 2;
    return;
  }

  var lock = UpstreamLock.fromJson(
    jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>,
  );

  const dtsContent = _dtsTemplate;
  final fixtureDocsPath = p.join(
    packageRoot,
    'tool',
    'fixtures',
    'f2pb_js_vkp.html',
  );
  final fixtureSdkPath = p.join(
    packageRoot,
    'tool',
    'fixtures',
    'mailru.core.js',
  );
  final docsContent = File(fixtureDocsPath).readAsStringSync();
  final sdkBytes = File(fixtureSdkPath).readAsBytesSync();

  final expectedLock = lock.copyWith(
    sdkSha512: sha512Hex(sdkBytes),
    docsHash: sha256Hex(utf8.encode(docsContent)),
    declarationHash: sha256Hex(utf8.encode(dtsContent)),
  );

  final lockMismatches = _lockMismatches(lock, expectedLock);
  if (lockMismatches.isNotEmpty && !options.bump) {
    stderr.writeln('Upstream lock mismatch:');
    for (final line in lockMismatches) {
      stderr.writeln(' - $line');
    }
    stderr.writeln('Run: dart run tool/generate.dart --bump');
    exitCode = 1;
    return;
  }

  if (options.bump) {
    lock = expectedLock;
    lockFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n',
    );
  }

  final parser = TypeScriptIrParser.fromSharedCore(
    currentPackageRoot: packageRoot,
  );
  await parser.ensureDependencies();

  final tempDir = await Directory.systemTemp.createTemp('vkplay_codegen_');
  try {
    final tempDtsPath = p.join(tempDir.path, 'vkplay_sdk.d.ts');
    File(tempDtsPath).writeAsStringSync(dtsContent);

    final ir = await parser.parseFileToIr(tempDtsPath);
    final rawCode = _emitRawCode(lock.sdkVersion);

    final edits = GenerationEdits();

    checkOrWriteGeneratedFile(
      path: dtsOutputPath,
      content: dtsContent,
      checkOnly: options.checkOnly,
      edits: edits,
    );

    checkOrWriteGeneratedFile(
      path: rawOutputPath,
      content: rawCode,
      checkOnly: options.checkOnly,
      edits: edits,
    );

    final parserSymbols = (ir['symbols']! as List<dynamic>).cast<String>();
    final symbols = _extractSymbols(
      dtsContent: dtsContent,
      parserSymbols: parserSymbols,
    );
    final newSnapshot = <String, Object?>{
      'sdkVersion': lock.sdkVersion,
      'symbols': symbols,
    };

    final snapshotFile = File(snapshotPath);
    final oldSnapshot = snapshotFile.existsSync()
        ? jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>
        : <String, Object?>{'symbols': <Object?>[]};

    final oldSymbols = (oldSnapshot['symbols'] as List<dynamic>? ?? <dynamic>[])
        .cast<String>()
        .toSet();
    final newSymbols = symbols.toSet();

    final diff = buildApiDiff(
      fromVersion: oldSnapshot['sdkVersion'],
      toVersion: lock.sdkVersion,
      oldSymbols: oldSymbols,
      newSymbols: newSymbols,
      fromVersionField: 'fromVersion',
      toVersionField: 'toVersion',
    );

    checkOrWriteGeneratedFile(
      path: snapshotPath,
      content: '${const JsonEncoder.withIndent('  ').convert(newSnapshot)}\n',
      checkOnly: options.checkOnly,
      edits: edits,
    );

    checkOrWriteGeneratedFile(
      path: diffPath,
      content: '${const JsonEncoder.withIndent('  ').convert(diff)}\n',
      checkOnly: options.checkOnly,
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

    if (!options.checkOnly) {
      stdout.writeln('Generated files:');
      for (final file in edits.touchedFiles) {
        stdout.writeln(' - ${p.relative(file, from: packageRoot)}');
      }
      if (lockMismatches.isNotEmpty && options.bump) {
        stdout.writeln(
          'Updated lock file: ${p.relative(lockPath, from: packageRoot)}',
        );
      }
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

GenerateOptions? _parseOptions(final List<String> args) {
  var checkOnly = false;
  var bump = false;

  for (final arg in args) {
    switch (arg) {
      case '--check':
        checkOnly = true;
      case '--bump':
        bump = true;
      case '--help':
        stdout.writeln('Usage: dart run tool/generate.dart [--check] [--bump]');
        return null;
      default:
        stderr.writeln('Unknown option: $arg');
        return null;
    }
  }

  return GenerateOptions(checkOnly: checkOnly, bump: bump);
}

List<String> _lockMismatches(
  final UpstreamLock lock,
  final UpstreamLock expected,
) {
  final mismatches = <String>[];
  if (lock.sdkSha512 != expected.sdkSha512) {
    mismatches.add(
      'sdkSha512 lock=${lock.sdkSha512} actual=${expected.sdkSha512}',
    );
  }
  if (lock.docsHash != expected.docsHash) {
    mismatches.add(
      'docsHash lock=${lock.docsHash} actual=${expected.docsHash}',
    );
  }
  if (lock.declarationHash != expected.declarationHash) {
    mismatches.add(
      'declarationHash lock=${lock.declarationHash} actual=${expected.declarationHash}',
    );
  }
  return mismatches;
}

String _emitRawCode(final String sdkVersion) {
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: vkplay-iframe-api@$sdkVersion
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('iframeApi')
external VkPlayApiRaw? get iframeApi;

extension type VkPlayApiRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> init([JSAny? options]);
  external JSPromise<JSAny?> getLoginStatus();
  external JSPromise<JSAny?> userInfo();
  external JSPromise<JSAny?> userProfile();
  external JSPromise<JSAny?> userFriends([JSAny? options]);
  external JSPromise<JSAny?> userSocialFriends([JSAny? options]);
  external JSPromise<JSAny?> showInviteBox(JSAny? payload);
  external JSPromise<JSAny?> postToFeed(JSAny? payload);
}
''';
}

List<String> _extractSymbols({
  required final String dtsContent,
  required final List<String> parserSymbols,
}) {
  final symbols = <String>{...parserSymbols};
  final regex = RegExp(
    r'^(?:interface|type|enum|declare const)\s+([A-Za-z_][A-Za-z0-9_]*)',
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

const String _dtsTemplate = '''
interface VkPlayLoginStatus {
  authorized: boolean;
  userId?: string;
}

interface VkPlayUserInfo {
  id: string;
  name?: string;
  displayName?: string;
  avatar?: string;
  avatarUrl?: string;
}

interface VkPlayUserProfile {
  id: string;
  name?: string;
  displayName?: string;
  nickname?: string;
  avatar?: string;
  avatarUrl?: string;
}

interface VkPlayFriend {
  id: string;
  name?: string;
  displayName?: string;
  nickname?: string;
  avatar?: string;
  avatarUrl?: string;
}

interface VkPlayApi {
  init(options?: { app_id?: string }): Promise<any>;
  getLoginStatus(): Promise<VkPlayLoginStatus>;
  userInfo(): Promise<VkPlayUserInfo>;
  userProfile(): Promise<VkPlayUserProfile>;
  userFriends(options?: { limit?: number; offset?: number }): Promise<VkPlayFriend[]>;
  userSocialFriends(options?: { limit?: number; offset?: number }): Promise<VkPlayFriend[]>;
  showInviteBox(payload: any): Promise<any>;
  postToFeed(payload: any): Promise<any>;
}

declare const iframeApi: VkPlayApi;
''';
