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
    required this.officialDtsUrl,
  });

  final String sdkUrl;
  final String sdkSha512;
  final String sdkVersion;
  final List<String> docsUrls;
  final String docsHash;
  final String declarationHash;
  final String? officialDtsUrl;

  UpstreamLock copyWith({
    final String? sdkUrl,
    final String? sdkSha512,
    final String? sdkVersion,
    final List<String>? docsUrls,
    final String? docsHash,
    final String? declarationHash,
    final String? officialDtsUrl,
    final bool clearOfficialDtsUrl = false,
  }) => UpstreamLock(
    sdkUrl: sdkUrl ?? this.sdkUrl,
    sdkSha512: sdkSha512 ?? this.sdkSha512,
    sdkVersion: sdkVersion ?? this.sdkVersion,
    docsUrls: docsUrls ?? this.docsUrls,
    docsHash: docsHash ?? this.docsHash,
    declarationHash: declarationHash ?? this.declarationHash,
    officialDtsUrl: clearOfficialDtsUrl
        ? null
        : (officialDtsUrl ?? this.officialDtsUrl),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'sdkUrl': sdkUrl,
    'sdkSha512': sdkSha512,
    'sdkVersion': sdkVersion,
    'docsUrls': docsUrls,
    'docsHash': docsHash,
    'declarationHash': declarationHash,
    'officialDtsUrl': officialDtsUrl,
  };

  static UpstreamLock fromJson(final Map<String, Object?> json) => UpstreamLock(
    sdkUrl: json['sdkUrl']! as String,
    sdkSha512: json['sdkSha512']! as String,
    sdkVersion: json['sdkVersion']! as String,
    docsUrls: (json['docsUrls']! as List<dynamic>).cast<String>(),
    docsHash: json['docsHash']! as String,
    declarationHash: json['declarationHash']! as String,
    officialDtsUrl: json['officialDtsUrl'] as String?,
  );
}

final class GenerateOptions {
  const GenerateOptions({required this.checkOnly, required this.bump});

  final bool checkOnly;
  final bool bump;
}

final class RuntimeMember {
  const RuntimeMember({required this.name, required this.isMethod});

  final String name;
  final bool isMethod;
}

final class RuntimeSurface {
  const RuntimeSurface({
    required this.version,
    required this.sha512,
    required this.moduleMembers,
    required this.symbols,
  });

  final String version;
  final String sha512;
  final Map<String, List<RuntimeMember>> moduleMembers;
  final Set<String> symbols;
}

final class DocsExtraction {
  const DocsExtraction({
    required this.pages,
    required this.hash,
    required this.methodsByModule,
  });

  final Map<Uri, String> pages;
  final String hash;
  final Map<String, Set<String>> methodsByModule;
}

final class DtsResult {
  const DtsResult({
    required this.content,
    required this.officialUrl,
    required this.hash,
  });

  final String content;
  final String? officialUrl;
  final String hash;
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
    'crazygames_sdk.generated.d.ts',
  );
  final rawOutputPath = p.join(
    packageRoot,
    'lib',
    'src',
    'raw',
    'crazygames_raw.g.dart',
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

  final docs = await _fetchDocs(lock.docsUrls);
  final runtime = await _fetchRuntime(lock.sdkUrl);
  final dts = await _resolveDts(docs: docs, runtime: runtime, lock: lock);

  final expectedLock = lock.copyWith(
    sdkSha512: runtime.sha512,
    sdkVersion: runtime.version,
    docsHash: docs.hash,
    declarationHash: dts.hash,
    officialDtsUrl: dts.officialUrl,
    clearOfficialDtsUrl: dts.officialUrl == null,
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

  final tempDir = await Directory.systemTemp.createTemp('crazygames_codegen_');
  try {
    final tempDtsPath = p.join(tempDir.path, 'crazygames_sdk.d.ts');
    File(tempDtsPath).writeAsStringSync(dts.content);

    final ir = await parser.parseFileToIr(tempDtsPath);
    final rawCode = emitRawCode(ir, lock);

    final edits = GenerationEdits();

    checkOrWriteGeneratedFile(
      path: dtsOutputPath,
      content: dts.content,
      checkOnly: options.checkOnly,
      edits: edits,
    );
    checkOrWriteGeneratedFile(
      path: rawOutputPath,
      content: rawCode,
      checkOnly: options.checkOnly,
      edits: edits,
    );

    final symbols = ((ir['symbols']! as List<dynamic>).cast<String>()..sort());
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
  if (lock.sdkVersion != expected.sdkVersion) {
    mismatches.add(
      'sdkVersion lock=${lock.sdkVersion} actual=${expected.sdkVersion}',
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
  if (lock.officialDtsUrl != expected.officialDtsUrl) {
    mismatches.add(
      'officialDtsUrl lock=${lock.officialDtsUrl} actual=${expected.officialDtsUrl}',
    );
  }
  return mismatches;
}

Future<DocsExtraction> _fetchDocs(final List<String> urls) async {
  final pages = <Uri, String>{};
  final normalizedForHash = <Uri, String>{};

  final methodsByModule = <String, Set<String>>{
    'ad': <String>{},
    'banner': <String>{},
    'game': <String>{},
    'user': <String>{},
    'data': <String>{},
    'analytics': <String>{},
  };

  for (final raw in urls) {
    final uri = Uri.parse(raw);
    final response = await _httpGet(uri);
    if (response.statusCode != 200) {
      throw StateError(
        'Failed to fetch docs URL $raw: HTTP ${response.statusCode}',
      );
    }

    final html = response.body;
    pages[uri] = html;

    final codeBlocks = _extractCodeBlocks(html);
    normalizedForHash[uri] = codeBlocks.join('\n----\n');

    for (final block in codeBlocks) {
      final methodPattern = RegExp(
        r'window\.CrazyGames\.SDK\.([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_]+)\s*\(',
      );
      for (final match in methodPattern.allMatches(block)) {
        final module = match.group(1)!;
        final method = match.group(2)!;
        methodsByModule.putIfAbsent(module, () => <String>{}).add(method);
      }
    }
  }

  final concatenated = StringBuffer();
  for (final uri
      in normalizedForHash.keys.toList()
        ..sort((final a, final b) => a.toString().compareTo(b.toString()))) {
    concatenated
      ..writeln(uri)
      ..writeln(normalizedForHash[uri]);
  }

  return DocsExtraction(
    pages: pages,
    hash: sha256Hex(utf8.encode(concatenated.toString())),
    methodsByModule: methodsByModule,
  );
}

Future<RuntimeSurface> _fetchRuntime(final String sdkUrl) async {
  final response = await _httpGet(Uri.parse(sdkUrl));
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to fetch SDK script $sdkUrl: HTTP ${response.statusCode}',
    );
  }

  final source = response.body;
  final bytes = utf8.encode(source);
  final sha512 = sha512Hex(bytes);

  final versionMatch = RegExp('version:"([^"]+)"').firstMatch(source);
  final version = versionMatch?.group(1) ?? 'unknown';

  final moduleMembers = <String, List<RuntimeMember>>{};
  for (final module in <String>[
    'ad',
    'banner',
    'game',
    'user',
    'data',
    'analytics',
  ]) {
    final objectLiteral = _extractFailModeModuleObject(source, module);
    if (objectLiteral == null) {
      moduleMembers[module] = const <RuntimeMember>[];
      continue;
    }
    moduleMembers[module] = _parseTopLevelMembers(objectLiteral);
  }

  final symbols = <String>{};
  for (final entry in moduleMembers.entries) {
    for (final member in entry.value) {
      symbols.add('${entry.key}.${member.name}');
    }
  }

  return RuntimeSurface(
    version: version,
    sha512: sha512,
    moduleMembers: moduleMembers,
    symbols: symbols,
  );
}

Future<DtsResult> _resolveDts({
  required final DocsExtraction docs,
  required final RuntimeSurface runtime,
  required final UpstreamLock lock,
}) async {
  final officialCandidates = <String>{
    if (lock.officialDtsUrl != null) lock.officialDtsUrl!,
    'https://sdk.crazygames.com/crazygames-sdk-v3.d.ts',
    'https://sdk.crazygames.com/crazygames-sdk.d.ts',
    'https://sdk.crazygames.com/types/crazygames-sdk-v3.d.ts',
  };

  for (final url in officialCandidates) {
    final uri = Uri.parse(url);
    final response = await _httpGet(uri, allow404: true);
    if (response.statusCode != 200) {
      continue;
    }
    if (!response.body.contains('interface') ||
        !response.body.contains('CrazyGames')) {
      continue;
    }

    final content = _normalizeFileContent(response.body);
    return DtsResult(
      content: content,
      officialUrl: url,
      hash: sha256Hex(utf8.encode(content)),
    );
  }

  final content = _synthesizeDtsFromDocsAndRuntime(
    docs: docs,
    runtime: runtime,
  );
  return DtsResult(
    content: content,
    officialUrl: null,
    hash: sha256Hex(utf8.encode(content)),
  );
}

String _synthesizeDtsFromDocsAndRuntime({
  required final DocsExtraction docs,
  required final RuntimeSurface runtime,
}) {
  final declaredMethods = <String, Set<String>>{
    'ad': <String>{
      'requestAd',
      'hasAdblock',
      'addAdblockPopupListener',
      'removeAdblockPopupListener',
      'prefetchAd',
    },
    'banner': <String>{
      'requestBanner',
      'requestResponsiveBanner',
      'prefetchBanner',
      'prefetchResponsiveBanner',
      'renderPrefetchedBanner',
      'clearBanner',
      'clearAllBanners',
      'requestOverlayBanners',
    },
    'game': <String>{
      'link',
      'id',
      'settings',
      'isInstantJoin',
      'isInstantMultiplayer',
      'inviteParams',
      'happytime',
      'gameplayStart',
      'gameplayStop',
      'loadingStart',
      'loadingStop',
      'inviteLink',
      'showInviteButton',
      'hideInviteButton',
      'getInviteParam',
      'addSettingsChangeListener',
      'removeSettingsChangeListener',
      'addJoinRoomListener',
      'removeJoinRoomListener',
    },
    'user': <String>{
      'isUserAccountAvailable',
      'systemInfo',
      'showAuthPrompt',
      'showAccountLinkPrompt',
      'getUser',
      'addAuthListener',
      'removeAuthListener',
      'getUserToken',
      'getXsollaUserToken',
      'listFriends',
      'addScore',
      'addScoreEncrypted',
      'submitScore',
    },
    'data': <String>{
      'clear',
      'getItem',
      'removeItem',
      'setItem',
      'syncUnityGameData',
    },
    'analytics': <String>{'trackOrder'},
  };

  final runtimeOnly = <String, List<RuntimeMember>>{};
  const ignoredRuntimeOnly = <String, Set<String>>{
    'ad': <String>{'isAdPlaying'},
    'banner': <String>{'activeBannersCount'},
  };
  for (final entry in runtime.moduleMembers.entries) {
    final declared = declaredMethods[entry.key] ?? <String>{};
    final fromDocs = docs.methodsByModule[entry.key] ?? <String>{};
    final ignored = ignoredRuntimeOnly[entry.key] ?? <String>{};
    final unknown = entry.value
        .where(
          (final member) =>
              !ignored.contains(member.name) &&
              !declared.contains(member.name) &&
              !fromDocs.contains(member.name),
        )
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      runtimeOnly[entry.key] = unknown;
    }
  }

  if (runtimeOnly.isNotEmpty) {
    stderr.writeln(
      'Warning: runtime/docs divergence detected. Adding permissive raw signatures for:',
    );
    for (final entry in runtimeOnly.entries) {
      stderr.writeln(
        ' - ${entry.key}: ${entry.value.map((final m) => m.name).join(', ')}',
      );
    }
  }

  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln(
      '// Source: synthesized from CrazyGames docs + runtime SDK script',
    )
    ..writeln('// SDK version: ${runtime.version}')
    ..writeln('// Docs URLs:')
    ..writeln(
      '//  - ${docs.pages.keys.map((final u) => u.toString()).join('\n//  - ')}',
    )
    ..writeln()
    ..writeln('export type Environment = "crazygames" | "local" | "disabled";')
    ..writeln('export type AdType = "midgame" | "rewarded";')
    ..writeln('export type PaymentProvider = "xsolla";')
    ..writeln('export type AdblockPopupState = "open";')
    ..writeln('export type DeviceType = "desktop" | "tablet" | "mobile";')
    ..writeln(
      'export type ApplicationType = "google_play_store" | "apple_store" | "pwa" | "web";',
    )
    ..writeln()
    ..writeln('export interface SdkError {')
    ..writeln('  code: string;')
    ..writeln('  message: string;')
    ..writeln('  containerId?: string;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface User {')
    ..writeln('  id?: string;')
    ..writeln('  username: string;')
    ..writeln('  profilePictureUrl: string;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface BrowserInfo {')
    ..writeln('  name: string;')
    ..writeln('  version: string;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface OsInfo {')
    ..writeln('  name: string;')
    ..writeln('  version: string;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface DeviceInfo {')
    ..writeln('  type: DeviceType;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface SystemInfo {')
    ..writeln('  countryCode: string;')
    ..writeln('  locale: string;')
    ..writeln('  device: DeviceInfo;')
    ..writeln('  os: OsInfo;')
    ..writeln('  browser: BrowserInfo;')
    ..writeln('  applicationType: ApplicationType;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface Friend {')
    ..writeln('  id: string;')
    ..writeln('  username: string;')
    ..writeln('  profilePictureUrl: string;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface FriendsPage {')
    ..writeln('  friends: Friend[];')
    ..writeln('  page: number;')
    ..writeln('  size: number;')
    ..writeln('  hasMore: boolean;')
    ..writeln('  total: number;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface FriendsListOptions {')
    ..writeln('  page: number;')
    ..writeln('  size: number;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface AccountLinkResponse {')
    ..writeln('  response: "yes" | "no";')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface GameSettings {')
    ..writeln('  disableChat: boolean;')
    ..writeln('  muteAudio: boolean;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface BannerRequest {')
    ..writeln('  id: string;')
    ..writeln('  width: number;')
    ..writeln('  height: number;')
    ..writeln('  x?: number;')
    ..writeln('  y?: number;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface OverlayBannerRequest {')
    ..writeln('  id: string;')
    ..writeln('  size: string;')
    ..writeln('  anchor: { x: number; y: number };')
    ..writeln('  position: { x: number; y: number };')
    ..writeln('  pivot?: { x: number; y: number };')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesAdCallbacks {')
    ..writeln('  adStarted?: () => void;')
    ..writeln('  adFinished?: () => void;')
    ..writeln('  adError?: (error: SdkError) => void;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesAd {')
    ..writeln('  prefetchAd(adType: AdType): void;')
    ..writeln(
      '  requestAd(adType: AdType, callbacks?: CrazyGamesAdCallbacks): Promise<void>;',
    )
    ..writeln('  hasAdblock(): Promise<boolean>;')
    ..writeln(
      '  addAdblockPopupListener(listener: (state: AdblockPopupState) => void): void;',
    )
    ..writeln(
      '  removeAdblockPopupListener(listener: (state: AdblockPopupState) => void): void;',
    )
    ..writeln('  isAdPlaying: boolean;')
    ..write(_runtimeExtrasTs(runtimeOnly['ad']))
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesBanner {')
    ..writeln(
      '  prefetchBanner(request: BannerRequest): Promise<{ id: string; banner: BannerRequest; renderOptions: Record<string, unknown> }>;',
    )
    ..writeln('  requestBanner(request: BannerRequest): Promise<void>;')
    ..writeln(
      '  prefetchResponsiveBanner(request: { id: string; width: number; height: number }): Promise<{ id: string; banner: BannerRequest; renderOptions: Record<string, unknown> }>;',
    )
    ..writeln('  requestResponsiveBanner(id: string): Promise<void>;')
    ..writeln(
      '  renderPrefetchedBanner(request: { id: string; banner: BannerRequest; renderOptions: Record<string, unknown> }): Promise<void>;',
    )
    ..writeln('  clearBanner(id: string): void;')
    ..writeln('  clearAllBanners(): void;')
    ..writeln(
      '  requestOverlayBanners(banners: OverlayBannerRequest[], callback?: (id: string, event: string, value?: string) => void): void;',
    )
    ..writeln('  activeBannersCount: number;')
    ..write(_runtimeExtrasTs(runtimeOnly['banner']))
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesGame {')
    ..writeln('  link: string;')
    ..writeln('  id: string;')
    ..writeln('  settings: GameSettings;')
    ..writeln('  isInstantJoin: boolean;')
    ..writeln('  isInstantMultiplayer: boolean;')
    ..writeln('  inviteParams: Record<string, string> | null;')
    ..writeln('  happytime(): void;')
    ..writeln('  gameplayStart(): void;')
    ..writeln('  gameplayStop(): void;')
    ..writeln('  loadingStart(): void;')
    ..writeln('  loadingStop(): void;')
    ..writeln('  inviteLink(params: Record<string, string>): string;')
    ..writeln('  showInviteButton(params: Record<string, string>): string;')
    ..writeln('  hideInviteButton(): void;')
    ..writeln('  getInviteParam(key: string): string | null;')
    ..writeln(
      '  addSettingsChangeListener(listener: (settings: GameSettings) => void): void;',
    )
    ..writeln(
      '  removeSettingsChangeListener(listener: (settings: GameSettings) => void): void;',
    )
    ..writeln(
      '  addJoinRoomListener(listener: (inviteParams: Record<string, string>) => void): void;',
    )
    ..writeln(
      '  removeJoinRoomListener(listener: (inviteParams: Record<string, string>) => void): void;',
    )
    ..write(_runtimeExtrasTs(runtimeOnly['game']))
    ..writeln('}')
    ..writeln()
    ..writeln('/** Experimental runtime-only surface from sdk/game-v2. */')
    ..writeln('export interface CrazyGamesGameV2 {')
    ..writeln(
      '  updateRoom(options: { roomId: string; isJoinable?: boolean; inviteParams?: Record<string, string> | null }): void;',
    )
    ..writeln('  leftRoom(): void;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesUser {')
    ..writeln('  isUserAccountAvailable: boolean;')
    ..writeln('  systemInfo: SystemInfo;')
    ..writeln('  showAuthPrompt(): Promise<User | null>;')
    ..writeln('  showAccountLinkPrompt(): Promise<AccountLinkResponse>;')
    ..writeln('  getUser(): Promise<User | null>;')
    ..writeln('  addAuthListener(listener: (user: User | null) => void): void;')
    ..writeln(
      '  removeAuthListener(listener: (user: User | null) => void): void;',
    )
    ..writeln('  getUserToken(): Promise<string>;')
    ..writeln('  getXsollaUserToken(): Promise<string>;')
    ..writeln(
      '  listFriends(options: FriendsListOptions): Promise<FriendsPage>;',
    )
    ..writeln('  addScore(score: number): void;')
    ..writeln(
      '  addScoreEncrypted(score: number, encryptedScore: string): void;',
    )
    ..writeln('  submitScore(payload: { encryptedScore: string }): void;')
    ..write(_runtimeExtrasTs(runtimeOnly['user']))
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesData {')
    ..writeln('  clear(): void;')
    ..writeln('  getItem(key: string): string | null;')
    ..writeln('  removeItem(key: string): void;')
    ..writeln(
      '  setItem(key: string, value: string | number | boolean | null): void;',
    )
    ..writeln('  syncUnityGameData(): void;')
    ..write(_runtimeExtrasTs(runtimeOnly['data']))
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesAnalytics {')
    ..writeln(
      '  trackOrder(provider: PaymentProvider, order: Record<string, unknown>): void;',
    )
    ..write(_runtimeExtrasTs(runtimeOnly['analytics']))
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesSdk {')
    ..writeln('  init(): Promise<void>;')
    ..writeln('  ad: CrazyGamesAd;')
    ..writeln('  banner: CrazyGamesBanner;')
    ..writeln('  game: CrazyGamesGame;')
    ..writeln('  /** Experimental runtime-only surface from sdk/game-v2. */')
    ..writeln('  "game-v2"?: CrazyGamesGameV2;')
    ..writeln('  user: CrazyGamesUser;')
    ..writeln('  data: CrazyGamesData;')
    ..writeln('  analytics: CrazyGamesAnalytics;')
    ..writeln('  environment: Environment;')
    ..writeln('  isQaTool: boolean;')
    ..writeln('}')
    ..writeln()
    ..writeln('export interface CrazyGamesGlobal {')
    ..writeln('  SDK: CrazyGamesSdk;')
    ..writeln('}')
    ..writeln()
    ..writeln('declare global {')
    ..writeln('  interface Window {')
    ..writeln('    CrazyGames: CrazyGamesGlobal;')
    ..writeln('  }')
    ..writeln('  const CrazyGames: CrazyGamesGlobal;')
    ..writeln('}')
    ..writeln()
    ..writeln('export {};');

  return _normalizeFileContent('$b');
}

String _runtimeExtrasTs(final List<RuntimeMember>? members) {
  if (members == null || members.isEmpty) {
    return '';
  }

  final b = StringBuffer();
  final emitted = <String>{};
  for (final member in members) {
    if (!emitted.add(member.name)) {
      continue;
    }
    final key = _tsPropertyKey(member.name);
    if (member.isMethod) {
      b.writeln('  /** Runtime-only permissive signature. */');
      b.writeln('  $key(...args: any[]): any;');
    } else {
      b.writeln('  /** Runtime-only permissive signature. */');
      b.writeln('  $key: any;');
    }
  }
  return _normalizeFileContent('$b');
}

String _tsPropertyKey(final String name) {
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
    return name;
  }
  return '"${name.replaceAll('"', r'\"')}"';
}

String? _extractFailModeModuleObject(final String source, final String module) {
  final token = 'get $module(){return{';
  final start = source.indexOf(token);
  if (start < 0) {
    return null;
  }

  final objectStart = start + token.length;
  var depth = 1;
  var inSingle = false;
  var inDouble = false;
  var inTemplate = false;
  var escaped = false;

  for (var i = objectStart; i < source.length; i++) {
    final ch = source[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (ch == r'\') {
      escaped = true;
      continue;
    }

    if (inSingle) {
      if (ch == "'") inSingle = false;
      continue;
    }
    if (inDouble) {
      if (ch == '"') inDouble = false;
      continue;
    }
    if (inTemplate) {
      if (ch == '`') inTemplate = false;
      continue;
    }

    if (ch == "'") {
      inSingle = true;
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      continue;
    }
    if (ch == '`') {
      inTemplate = true;
      continue;
    }

    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(objectStart, i);
      }
    }
  }

  return null;
}

List<RuntimeMember> _parseTopLevelMembers(final String objectLiteral) {
  final chunks = <String>[];
  final current = StringBuffer();

  var brace = 0;
  var bracket = 0;
  var paren = 0;
  var inSingle = false;
  var inDouble = false;
  var inTemplate = false;
  var escaped = false;

  for (var i = 0; i < objectLiteral.length; i++) {
    final ch = objectLiteral[i];

    if (escaped) {
      current.write(ch);
      escaped = false;
      continue;
    }

    if (ch == r'\') {
      current.write(ch);
      escaped = true;
      continue;
    }

    if (inSingle) {
      current.write(ch);
      if (ch == "'") inSingle = false;
      continue;
    }
    if (inDouble) {
      current.write(ch);
      if (ch == '"') inDouble = false;
      continue;
    }
    if (inTemplate) {
      current.write(ch);
      if (ch == '`') inTemplate = false;
      continue;
    }

    if (ch == "'") {
      inSingle = true;
      current.write(ch);
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      current.write(ch);
      continue;
    }
    if (ch == '`') {
      inTemplate = true;
      current.write(ch);
      continue;
    }

    if (ch == '{') {
      brace++;
      current.write(ch);
      continue;
    }
    if (ch == '}') {
      brace--;
      current.write(ch);
      continue;
    }
    if (ch == '[') {
      bracket++;
      current.write(ch);
      continue;
    }
    if (ch == ']') {
      bracket--;
      current.write(ch);
      continue;
    }
    if (ch == '(') {
      paren++;
      current.write(ch);
      continue;
    }
    if (ch == ')') {
      paren--;
      current.write(ch);
      continue;
    }

    if (ch == ',' && brace == 0 && bracket == 0 && paren == 0) {
      final chunk = current.toString().trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
      current.clear();
      continue;
    }

    current.write(ch);
  }

  final tail = current.toString().trim();
  if (tail.isNotEmpty) {
    chunks.add(tail);
  }

  final members = <RuntimeMember>[];
  final seen = <String>{};
  for (final chunk in chunks) {
    final colonIndex = _findTopLevelColon(chunk);
    if (colonIndex <= 0) {
      continue;
    }

    final rawKey = chunk.substring(0, colonIndex).trim();
    final value = chunk.substring(colonIndex + 1).trim();
    final key = rawKey
        .replaceAll(RegExp('''^['"]'''), '')
        .replaceAll(RegExp(r'''['"]$'''), '')
        .trim();
    final normalizedKey = key.replaceAll(RegExp('[^A-Za-z0-9_-]'), '').trim();
    if (normalizedKey.isEmpty || !seen.add(normalizedKey)) {
      continue;
    }

    final isMethod = value.startsWith('function') || value.contains('=>');
    members.add(RuntimeMember(name: normalizedKey, isMethod: isMethod));
  }

  return members;
}

int _findTopLevelColon(final String input) {
  var brace = 0;
  var bracket = 0;
  var paren = 0;
  var inSingle = false;
  var inDouble = false;
  var inTemplate = false;
  var escaped = false;

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (ch == r'\') {
      escaped = true;
      continue;
    }

    if (inSingle) {
      if (ch == "'") inSingle = false;
      continue;
    }
    if (inDouble) {
      if (ch == '"') inDouble = false;
      continue;
    }
    if (inTemplate) {
      if (ch == '`') inTemplate = false;
      continue;
    }

    if (ch == "'") {
      inSingle = true;
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      continue;
    }
    if (ch == '`') {
      inTemplate = true;
      continue;
    }

    if (ch == '{') {
      brace++;
      continue;
    }
    if (ch == '}') {
      brace--;
      continue;
    }
    if (ch == '[') {
      bracket++;
      continue;
    }
    if (ch == ']') {
      bracket--;
      continue;
    }
    if (ch == '(') {
      paren++;
      continue;
    }
    if (ch == ')') {
      paren--;
      continue;
    }

    if (ch == ':' && brace == 0 && bracket == 0 && paren == 0) {
      return i;
    }
  }

  return -1;
}

List<String> _extractCodeBlocks(final String html) {
  final blocks = <String>[];
  final pattern = RegExp(
    r'<div class="highlight"><pre>([\s\S]*?)</pre></div>',
    multiLine: true,
  );

  for (final match in pattern.allMatches(html)) {
    final content = match.group(1);
    if (content == null || content.isEmpty) {
      continue;
    }
    final text = _decodeHtmlEntities(
      content,
    ).replaceAll(RegExp('<[^>]+>'), '').replaceAll('\r', '').trim();
    if (text.isNotEmpty) {
      blocks.add(text);
    }
  }

  return blocks;
}

String _decodeHtmlEntities(final String input) => input
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');

String _normalizeFileContent(final String content) {
  var normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized
      .split('\n')
      .map((final line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
      .join('\n')
      .trimRight();
  return '$normalized\n';
}

final class _HttpTextResponse {
  const _HttpTextResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

Future<_HttpTextResponse> _httpGet(
  final Uri uri, {
  final bool allow404 = false,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (!allow404 && response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode} for $uri');
    }

    return _HttpTextResponse(statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

String emitRawCode(final Map<String, Object?> ir, final UpstreamLock lock) {
  final declarations = (ir['declarations']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final globalDeclarations = (ir['globalDeclarations']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final knownTypes = declarations
      .map((final d) => d['name']! as String)
      .toSet();

  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Source: CrazyGames SDK v${lock.sdkVersion}')
    ..writeln(
      '// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element',
    )
    ..writeln()
    ..writeln('@JS()')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'dart:js_interop';")
    ..writeln();

  for (final global in globalDeclarations) {
    if (global['kind'] != 'variable') {
      continue;
    }
    final name = global['name'] as String?;
    final typeIr = global['type'] as Map<String, Object?>?;
    if (name == null || typeIr == null || name != 'CrazyGames') {
      continue;
    }

    final mappedType = mapTypeToDart(
      typeIr,
      knownTypes: knownTypes,
      forReturn: true,
    );
    b
      ..writeln("@JS('CrazyGames')")
      ..writeln('external $mappedType get crazyGames;')
      ..writeln("@JS('CrazyGames.SDK')")
      ..writeln('external CrazyGamesSdkRaw get crazyGamesSdk;')
      ..writeln();
  }

  for (final declaration in declarations) {
    final kind = declaration['kind']! as String;

    switch (kind) {
      case 'interface':
        emitInterface(b, declaration, knownTypes);
      case 'typeAlias':
        emitTypeAlias(b, declaration, knownTypes);
      case 'enum':
        emitEnum(b, declaration);
      default:
        break;
    }
  }

  return '$b';
}

void emitInterface(
  final StringBuffer b,
  final Map<String, Object?> declaration,
  final Set<String> knownTypes,
) {
  final name = declaration['name']! as String;
  final members = (declaration['members']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final rawName = '${name}Raw';

  b.writeln('extension type $rawName(JSObject _) implements JSObject {');

  emitMembers(b, knownTypes: knownTypes, members: members, indent: '  ');

  b
    ..writeln('}')
    ..writeln();
}

void emitMembers(
  final StringBuffer b, {
  required final Set<String> knownTypes,
  required final List<Map<String, Object?>> members,
  required final String indent,
}) {
  final signatures = <String>{};

  for (final member in members) {
    final memberKind = member['kind'] as String?;

    switch (memberKind) {
      case 'property':
      case 'getter':
        final name = member['name'] as String?;
        if (name == null) {
          continue;
        }
        final dartName = safeIdentifier(name);
        final typeIr = member['type'] as Map<String, Object?>?;
        var typeName = mapTypeToDart(
          typeIr,
          knownTypes: knownTypes,
          forReturn: true,
        );
        if ((member['optional'] as bool?) ?? false) {
          typeName = makeNullable(typeName);
        }

        final signature = 'get:$name:$typeName';
        if (!signatures.add(signature)) {
          continue;
        }

        if (dartName != name) {
          b.writeln("$indent@JS('${escapeSingleQuotes(name)}')");
        }
        b.writeln('$indent external $typeName get $dartName;');

      case 'method':
        final name = member['name'] as String?;
        if (name == null) {
          continue;
        }
        final dartName = safeIdentifier(name);
        final params = (member['params'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, Object?>>();
        final returnTypeIr = member['returnType'] as Map<String, Object?>?;
        final returnType = mapTypeToDart(
          returnTypeIr,
          knownTypes: knownTypes,
          forReturn: true,
        );

        final parameterChunks = <String>[];
        var optionalStart = -1;

        for (var i = 0; i < params.length; i++) {
          final param = params[i];
          final paramName = safeIdentifier(
            param['name'] as String? ?? 'arg$i',
            fallback: 'arg$i',
          );
          final paramTypeIr = param['type'] as Map<String, Object?>?;
          var paramType = mapTypeToDart(
            paramTypeIr,
            knownTypes: knownTypes,
            forReturn: false,
          );
          final isOptional = (param['optional'] as bool?) ?? false;
          final isRest = (param['rest'] as bool?) ?? false;

          if (isRest) {
            paramType = 'JSArray<JSAny?>';
          }
          if (isOptional) {
            paramType = makeNullable(paramType);
            optionalStart = optionalStart == -1 ? i : optionalStart;
          }

          parameterChunks.add('$paramType $paramName');
        }

        final signature =
            'method:$name:$returnType:${parameterChunks.join(',')}';
        if (!signatures.add(signature)) {
          continue;
        }

        final paramsBuffer = StringBuffer();
        if (parameterChunks.isEmpty) {
          paramsBuffer.write('()');
        } else if (optionalStart == -1) {
          paramsBuffer.write('(${parameterChunks.join(', ')})');
        } else {
          final required = parameterChunks.take(optionalStart).toList();
          final optional = parameterChunks.skip(optionalStart).toList();
          paramsBuffer.write('(');
          if (required.isNotEmpty) {
            paramsBuffer.write(required.join(', '));
            if (optional.isNotEmpty) {
              paramsBuffer.write(', ');
            }
          }
          paramsBuffer.write('[');
          paramsBuffer.write(optional.join(', '));
          paramsBuffer.write(']');
          paramsBuffer.write(')');
        }

        if (dartName != name) {
          b.writeln("$indent@JS('${escapeSingleQuotes(name)}')");
        }
        b.writeln('$indent external $returnType $dartName$paramsBuffer;');

      case 'index':
        final returnTypeIr = member['returnType'] as Map<String, Object?>?;
        final returnType = mapTypeToDart(
          returnTypeIr,
          knownTypes: knownTypes,
          forReturn: true,
        );
        final signature = 'index:$returnType';
        if (!signatures.add(signature)) {
          continue;
        }
        b.writeln('$indent external $returnType operator [](JSAny? key);');

      default:
        break;
    }
  }
}

void emitTypeAlias(
  final StringBuffer b,
  final Map<String, Object?> declaration,
  final Set<String> knownTypes,
) {
  final name = declaration['name']! as String;
  final rawName = '${name}Raw';
  final typeParams =
      (declaration['typeParams'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, Object?>>();
  final typeIr = declaration['type'] as Map<String, Object?>?;

  final mappedType = mapTypeToDart(
    typeIr,
    knownTypes: knownTypes,
    forReturn: true,
  );

  if (typeParams.isEmpty) {
    b.writeln('typedef $rawName = $mappedType;');
  } else {
    final genericArgs = <String>[];
    for (var i = 0; i < typeParams.length; i++) {
      genericArgs.add('T$i extends JSAny?');
    }
    b.writeln('typedef $rawName<${genericArgs.join(', ')}> = $mappedType;');
  }

  final literalUnion =
      (declaration['literalUnion'] as List<dynamic>? ?? <dynamic>[])
          .cast<dynamic>();
  if (literalUnion.isNotEmpty) {
    final valuesClass = '${rawName}Values';
    b.writeln('abstract final class $valuesClass {');

    final usedNames = <String>{};
    for (final value in literalUnion) {
      final rawValue = value as String;
      var fieldName = safeIdentifier(toLowerCamel(rawValue));
      if (!usedNames.add(fieldName)) {
        fieldName = '${fieldName}_${usedNames.length}';
        usedNames.add(fieldName);
      }
      b.writeln(
        "  static JSString get $fieldName => '${escapeSingleQuotes(rawValue)}'.toJS;",
      );
    }

    b
      ..writeln('}')
      ..writeln();
  }
}

void emitEnum(final StringBuffer b, final Map<String, Object?> declaration) {
  final name = declaration['name']! as String;
  final rawName = '${name}Raw';
  final valuesClass = '${rawName}Values';
  b.writeln('typedef $rawName = JSString;');
  b.writeln('abstract final class $valuesClass {');

  final members = (declaration['members']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  for (final member in members) {
    final memberName = member['name']! as String;
    final value = member['value'];
    final fieldName = safeIdentifier(toLowerCamel(memberName));
    final stringValue = value is String ? value : '$value';
    b.writeln(
      "  static JSString get $fieldName => '${escapeSingleQuotes(stringValue)}'.toJS;",
    );
  }

  b
    ..writeln('}')
    ..writeln();
}
