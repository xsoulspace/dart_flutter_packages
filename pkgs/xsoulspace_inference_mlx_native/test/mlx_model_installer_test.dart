import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The DOWNLOADER lane gates (design `models-local-manager.md`): the
/// curated catalog, the hub-cache installer with the consent /
/// network / budget refusals, HTTP-Range resume, the marker-guarded
/// delete, and the discovery integration — an installed entry must be
/// found by [listCachedQwen3Snapshots] with no second registry.
///
/// Zero network: the installer's opener seam serves a canned in-memory
/// hub map.
final class _FakeHub {
  _FakeHub(this.repos, {this.honorRanges = true});

  /// repoId → fileName → bytes.
  final Map<String, Map<String, List<int>>> repos;

  final bool honorRanges;

  /// Every request, recorded as `<file>` (fresh fetch or probe) /
  /// `<file>@<offset>` (range fetch).
  final List<String> requests = <String>[];

  int get callCount => requests.length;

  Future<MlxRemoteModelFile?> call(Uri url, {int? resumeOffset}) async {
    final segments = url.pathSegments;
    final repoId = segments.take(segments.length - 3).join('/');
    final fileName = segments.last;
    requests.add(resumeOffset == null ? fileName : '$fileName@$resumeOffset');
    final bytes = repos[repoId]?[fileName];
    if (bytes == null) return null;
    if (resumeOffset != null &&
        resumeOffset > 0 &&
        honorRanges &&
        resumeOffset < bytes.length) {
      return MlxRemoteModelFile(
        contentLength: bytes.length - resumeOffset,
        resumeOffset: resumeOffset,
        body: Stream<List<int>>.value(bytes.sublist(resumeOffset)),
      );
    }
    return MlxRemoteModelFile(
      contentLength: bytes.length,
      body: Stream<List<int>>.value(bytes),
    );
  }
}

void main() {
  const configJson = '{"model_type": "qwen3", "hidden_size": 64}';
  const tokenizerJson = '{"model": "fake"}';
  const tokenizerConfigJson = '{"tokenizer_class": "PreTrainedTokenizerFast"}';
  final vocabBytes = utf8.encode('<|endoftext|>');
  final weights = List<int>.generate(1024, (i) => i & 0xff);

  Map<String, List<int>> fullRepo({
    bool withOptional = true,
    bool sharded = false,
  }) => <String, List<int>>{
    'config.json': utf8.encode(configJson),
    'tokenizer.json': utf8.encode(tokenizerJson),
    'tokenizer_config.json': utf8.encode(tokenizerConfigJson),
    if (withOptional) 'vocab.json': vocabBytes,
    if (withOptional) 'merges.txt': utf8.encode('Ġ t\nĠ a\n'),
    if (!sharded) 'model.safetensors': weights,
    if (sharded)
      'model.safetensors.index.json': utf8.encode(
        jsonEncode(<String, dynamic>{
          'weight_map': <String, String>{
            'a': 'model-00001-of-00002.safetensors',
            'b': 'model-00002-of-00002.safetensors',
          },
        }),
      ),
    if (sharded) 'model-00001-of-00002.safetensors': weights.sublist(0, 512),
    if (sharded) 'model-00002-of-00002.safetensors': weights.sublist(512),
  };

  Future<List<ProvisionProgress>> collectEvents(
    Stream<ProvisionProgress> stream,
  ) => stream.toList();

  Future<(List<ProvisionProgress>, MlxModelInstallRefusal)> collectRefusal(
    Stream<ProvisionProgress> stream,
  ) async {
    final events = <ProvisionProgress>[];
    final refusal = Completer<MlxModelInstallRefusal>();
    late final StreamSubscription<ProvisionProgress> sub;
    sub = stream.listen(
      events.add,
      onError: (Object e) {
        if (!refusal.isCompleted) refusal.complete(e as MlxModelInstallRefusal);
      },
      onDone: () {
        if (!refusal.isCompleted) {
          refusal.completeError(
            StateError('the install stream completed without a refusal'),
          );
        }
      },
    );
    final result = await refusal.future;
    await sub.cancel();
    return (events, result);
  }

  List<String> phaseNames(List<ProvisionProgress> events) {
    final seen = <String>{};
    for (final e in events) {
      seen.add(e.phase.name);
    }
    return seen.toList();
  }

  /// Writes a COMPLETE manager snapshot (config + texts + weights +
  /// marker) straight onto disk.
  Future<Directory> seedCompleteSnapshot(
    MlxModelInstaller installer,
    MlxModelCatalogEntry entry,
    Map<String, List<int>> files,
  ) async {
    final dir = Directory(installer.snapshotPath(entry))
      ..createSync(recursive: true);
    files.forEach(
      (name, bytes) => File('${dir.path}/$name').writeAsBytesSync(bytes),
    );
    File('${dir.path}/$mlxManagerMarkerFileName').writeAsStringSync('test\n');
    return dir;
  }

  test('the catalog pins the v1 entries + the LFM2.5 and laya '
      'lifecycle entries with unique repo ids', () {
    expect(mlxModelCatalog, hasLength(6));
    expect(mlxModelCatalog.map((e) => e.repoId).toSet(), hasLength(6));
    expect(
      mlxModelCatalog.map((e) => e.repoId),
      containsAll(<String>[
        'mlx-community/Qwen3-0.6B-4bit',
        'mlx-community/Qwen3.5-0.8B-4bit',
        'mlx-community/Qwen3-1.7B-4bit',
        'mlx-community/Qwen3-4B-4bit',
        // The `local:lfm` cast's checkpoint (2026-11-18 lifecycle law):
        // the manager's install IS the lane's provisioning.
        'LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit',
        // The decision lane's brain (2026-11-19 lifecycle law): the
        // DISK-ONLY row — the sidecar serves it out-of-process.
        'aac6fef/laya-mlx',
      ]),
    );
    for (final e in mlxModelCatalog) {
      expect(e.label, isNotEmpty);
      expect(e.family, anyOf('qwen3', 'qwen3.5', 'lfm2.5', 'laya'));
      expect(e.paramLabel, isNotEmpty);
      expect(e.approxDownloadBytes, greaterThan(0));
      if (e.family == 'laya') {
        // The decision checkpoint: fp16, and the engine's own law
        // (rl_agent_config.json + weights) is the whole requirement —
        // no tokenizer/config over-requirement that would 404.
        expect(e.quant, 'fp16');
        expect(e.requiredFiles, <String>['rl_agent_config.json']);
        expect(e.optionalFiles, isEmpty);
      } else {
        expect(e.quant, '4bit');
        expect(e.requiredFiles, contains('config.json'));
        expect(
          e.optionalFiles,
          containsAll(<String>['vocab.json', 'merges.txt']),
        );
      }
    }
  });

  test('every entry derives a hub dir name its discovery law accepts', () {
    // The QWEN discovery law's regex shape
    // (`models--<org>--Qwen3[.<n>]-<tail>`, org mlx-community); the LFM
    // resolver's law is a SUBSTRING (`*LFM2.5-1.2B*`); the laya
    // resolver's law is a SUBSTRING (`*laya-mlx*` requiring
    // rl_agent_config + weights) — three families, three laws, one
    // store.
    final qwenPattern = RegExp(
      r'^models--([A-Za-z0-9_.-]+)--(Qwen3(?:\.\d+)?)-(.+)$',
    );
    for (final e in mlxModelCatalog) {
      if (e.family.startsWith('qwen')) {
        expect(e.hubDirName, matches(qwenPattern));
        expect(e.org, 'mlx-community');
      } else if (e.family == 'lfm2.5') {
        expect(e.hubDirName, contains('LFM2.5-1.2B'));
        expect(e.org, 'LiquidAI');
      } else {
        expect(e.hubDirName, contains('laya-mlx'));
        expect(e.org, 'aac6fef');
      }
    }
  });

  test('approximate sizes grow with the parameter count (per family)', () {
    // The monotonic law holds WITHIN a family — the LFM2.5 1.2B entry
    // tails the list and is smaller than the Qwen3 4B by design.
    for (final family in <String>['qwen3', 'qwen3.5']) {
      final sizes = [
        for (final e in mlxModelCatalog)
          if (e.family == family) e.approxDownloadBytes,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]));
      }
    }
    final lfm = mlxModelCatalog.firstWhere((e) => e.family == 'lfm2.5');
    expect(lfm.approxDownloadBytes, greaterThan(500 * 1024 * 1024));
    expect(lfm.approxDownloadBytes, lessThan(800 * 1024 * 1024));
  });

  group('MlxModelInstaller.install', () {
    test('happy install writes the hub layout + marker and the discovery '
        'finds it', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final events = await collectEvents(
        installer.install(entry, userConsent: true),
      );

      expect(phaseNames(events), [
        'checking',
        'downloading',
        'loading',
        'ready',
      ]);
      final snapshotPath = installer.snapshotPath(entry);
      expect(File('$snapshotPath/config.json').readAsStringSync(), configJson);
      expect(
        File('$snapshotPath/model.safetensors').readAsBytesSync(),
        weights,
      );
      expect(File('$snapshotPath/tokenizer.json').existsSync(), isTrue);
      expect(File('$snapshotPath/vocab.json').existsSync(), isTrue);
      expect(File('$snapshotPath/merges.txt').existsSync(), isTrue);
      expect(
        File('$snapshotPath/$mlxManagerMarkerFileName').existsSync(),
        isTrue,
      );
      expect(
        Directory(snapshotPath)
            .listSync()
            .where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
      final ready = events.last;
      expect(ready.percent, 100);
      expect(ready.totalBytes, greaterThan(0));

      // THE integration assertion: the install needs no second
      // registry — the real discovery picks it up.
      final found = listCachedQwen3Snapshots(hubRoot: tmp.path)
          .where((s) => s.refName == 'qwen3-0.6b')
          .toList();
      expect(found, hasLength(1));
      expect(found.single.snapshotDir, snapshotPath);
    });

    test('a consent refusal touches no bytes', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final (events, refusal) = await collectRefusal(
        installer.install(entry, userConsent: false),
      );

      expect(refusal.code, 'user_consent_required');
      expect(events.last.phase, ProvisionPhase.failed);
      expect(events.last.message, contains('user_consent_required'));
      expect(tmp.listSync(), isEmpty); // no paths, no bytes
      expect(fake.requests, isEmpty);
    });

    test('a network-gate refusal touches no bytes', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
        isNetworkAllowed: () => false,
      );

      final (events, refusal) = await collectRefusal(
        installer.install(entry, userConsent: true),
      );

      expect(refusal.code, 'network_blocked');
      expect(events.last.phase, ProvisionPhase.failed);
      expect(tmp.listSync(), isEmpty);
      expect(fake.requests, isEmpty);
    });

    test('a max-size refusal fires before any download', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
        maxDownloadBytes: 64,
      );

      final (events, refusal) = await collectRefusal(
        installer.install(entry, userConsent: true),
      );

      expect(refusal.code, 'max_download_exceeded');
      expect(events.last.phase, ProvisionPhase.failed);
      expect(refusal.detail, contains('limit'));
      // The budget check precedes layout creation: nothing landed.
      expect(Directory(installer.snapshotPath(entry)).existsSync(), isFalse);
    });

    test(
      'an already-complete install short-circuits ready with no network',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'mlx_installer_test_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        final entry = mlxModelCatalog.first;
        final fake = _FakeHub({entry.repoId: fullRepo()});
        final installer = MlxModelInstaller(
          hubRoot: tmp.path,
          fileOpener: fake.call,
        );
        await seedCompleteSnapshot(installer, entry, fullRepo());

        final events = await collectEvents(
          installer.install(entry, userConsent: true),
        );

        expect(phaseNames(events), ['checking', 'ready']);
        expect(events.last.percent, 100);
        expect(fake.callCount, 0); // no probes, no bytes — genuinely installed
      },
    );

    test(
      'resume continues from a .part file and keeps complete files',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'mlx_installer_test_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        final entry = mlxModelCatalog.first;
        final fake = _FakeHub({entry.repoId: fullRepo()});
        final installer = MlxModelInstaller(
          hubRoot: tmp.path,
          fileOpener: fake.call,
        );
        final repo = fullRepo();
        final snapshotDir = Directory(installer.snapshotPath(entry))
          ..createSync(recursive: true);
        // config.json landed before the interruption; weights are partial.
        File('${snapshotDir.path}/config.json')
            .writeAsBytesSync(repo['config.json']!);
        File('${snapshotDir.path}/model.safetensors.part')
            .writeAsBytesSync(weights.sublist(0, 3));

        final events = await collectEvents(
          installer.install(entry, userConsent: true),
        );

        expect(phaseNames(events).last, 'ready');
        expect(
          File('${snapshotDir.path}/model.safetensors').readAsBytesSync(),
          weights,
        );
        expect(
          File('${snapshotDir.path}/model.safetensors.part').existsSync(),
          isFalse,
        );
        // The part resumed at its exact length, never re-fetched whole.
        expect(fake.requests, contains('model.safetensors@3'));
        expect(
          fake.requests.where((r) => r == 'model.safetensors'),
          hasLength(1), // the probe only — no full re-download
        );
        // config.json was probed once and KEPT, not re-downloaded.
        expect(fake.requests.where((r) => r == 'config.json'), hasLength(1));
      },
    );

    test('a range-ignoring server falls back to a fresh fetch', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()}, honorRanges: false);
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );
      final snapshotDir = Directory(installer.snapshotPath(entry))
        ..createSync(recursive: true);
      File('${snapshotDir.path}/model.safetensors.part')
          .writeAsBytesSync(weights.sublist(0, 3));

      final events = await collectEvents(
        installer.install(entry, userConsent: true),
      );

      expect(phaseNames(events).last, 'ready');
      expect(
        File('${snapshotDir.path}/model.safetensors').readAsBytesSync(),
        weights,
      );
      // The range attempt was made; the server ignored it, and the
      // full-body response IS the fresh fetch — no extra request.
      expect(fake.requests, contains('model.safetensors@3'));
      expect(
        fake.requests.where((r) => r == 'model.safetensors'),
        hasLength(1),
      );
    });

    test('optional files that 404 are skipped honestly', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo(withOptional: false)});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final events = await collectEvents(
        installer.install(entry, userConsent: true),
      );

      expect(phaseNames(events).last, 'ready');
      final snapshotPath = installer.snapshotPath(entry);
      expect(File('$snapshotPath/vocab.json').existsSync(), isFalse);
      expect(File('$snapshotPath/merges.txt').existsSync(), isFalse);
      expect(File('$snapshotPath/config.json').existsSync(), isTrue);
    });

    test('a missing required file refuses with the file named', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final repo = fullRepo()..remove('tokenizer.json');
      final fake = _FakeHub({entry.repoId: repo});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final (events, refusal) = await collectRefusal(
        installer.install(entry, userConsent: true),
      );

      expect(refusal.code, 'install_failed:tokenizer.json');
      expect(events.last.phase, ProvisionPhase.failed);
      expect(events.last.message, contains('tokenizer.json'));
    });

    test('a repo with no weights at all refuses with a named error', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final repo = fullRepo()
        ..remove('model.safetensors')
        ..remove('vocab.json')
        ..remove('merges.txt');
      final fake = _FakeHub({entry.repoId: repo});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final (_, refusal) = await collectRefusal(
        installer.install(entry, userConsent: true),
      );

      expect(refusal.code, 'install_failed:model.safetensors');
    });

    test('sharded weights resolve through the index weight_map', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final repo = fullRepo(sharded: true);
      final fake = _FakeHub({entry.repoId: repo});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final events = await collectEvents(
        installer.install(entry, userConsent: true),
      );

      expect(phaseNames(events).last, 'ready');
      final snapshotPath = installer.snapshotPath(entry);
      expect(
        File('$snapshotPath/model.safetensors.index.json').readAsBytesSync(),
        repo['model.safetensors.index.json'],
      );
      expect(
        File('$snapshotPath/model-00001-of-00002.safetensors')
            .readAsBytesSync(),
        weights.sublist(0, 512),
      );
      expect(
        File('$snapshotPath/model-00002-of-00002.safetensors')
            .readAsBytesSync(),
        weights.sublist(512),
      );
    });

    test('a concurrent second install of the same entry refuses', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );

      final first = installer.install(entry, userConsent: true);
      final firstDone = Completer<void>();
      final firstSub = first.listen(
        (_) {},
        onError: (Object e) {
          if (!firstDone.isCompleted) firstDone.completeError(e);
        },
        onDone: () {
          if (!firstDone.isCompleted) firstDone.complete();
        },
      );

      final (_, refusal) = await collectRefusal(
        installer.install(entry, userConsent: true),
      );
      expect(refusal.code, 'install_in_progress');

      // The first install is untouched by the refusal and completes
      // honestly; the test must NOT await an onDone after cancelling —
      // a cancelled subscription never delivers one.
      await firstDone.future;
      await firstSub.cancel();

      // The inflight slot is released with the finished install: a
      // follow-up install runs through to ready.
      final third = await collectEvents(
        installer.install(entry, userConsent: true),
      );
      expect(phaseNames(third).last, 'ready');
    });
  });

  group('InstalledState and delete', () {
    test(
      'stateOf flips notInstalled → installed with the snapshot path',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'mlx_installer_test_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        final entry = mlxModelCatalog.first;
        final fake = _FakeHub({entry.repoId: fullRepo()});
        final installer = MlxModelInstaller(
          hubRoot: tmp.path,
          fileOpener: fake.call,
        );

        final before = installer.stateOf(entry);
        expect(before.installed, isFalse);
        expect(before.snapshotDir, isNull);

        await collectEvents(installer.install(entry, userConsent: true));

        final after = installer.stateOf(entry);
        expect(after.installed, isTrue);
        expect(after.snapshotDir, installer.snapshotPath(entry));
      },
    );

    test(
      'an interrupted (marker-less) manager dir reads notInstalled',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'mlx_installer_test_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        final entry = mlxModelCatalog.first;
        final installer = MlxModelInstaller(hubRoot: tmp.path);
        final snapshotPath = installer.snapshotPath(entry);
        Directory(snapshotPath).createSync(recursive: true);
        File('$snapshotPath/config.json').writeAsStringSync(configJson);

        expect(installer.stateOf(entry).installed, isFalse);
      },
    );

    test('delete removes a manager-installed hub dir', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final fake = _FakeHub({entry.repoId: fullRepo()});
      final installer = MlxModelInstaller(
        hubRoot: tmp.path,
        fileOpener: fake.call,
      );
      await collectEvents(installer.install(entry, userConsent: true));

      expect(await installer.delete(entry), isTrue);
      expect(
        Directory('${tmp.path}/${entry.hubDirName}').existsSync(),
        isFalse,
      );
      // The discovery no longer sees it.
      expect(listCachedQwen3Snapshots(hubRoot: tmp.path), isEmpty);
    });

    test('delete refuses a foreign cache entry', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final installer = MlxModelInstaller(hubRoot: tmp.path);
      // A snapshot installed by a terminal / another tool: complete by
      // the discovery's law, but no manager marker anywhere.
      final foreign = Directory(
        '${tmp.path}/${entry.hubDirName}/snapshots/9f2a1c',
      )..createSync(recursive: true);
      File('${foreign.path}/config.json').writeAsStringSync(configJson);

      expect(await installer.delete(entry), isFalse);
      expect(foreign.existsSync(), isTrue);
    });

    test('delete refuses when a foreign snapshot shares the hub dir', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final installer = MlxModelInstaller(hubRoot: tmp.path);
      await seedCompleteSnapshot(installer, entry, fullRepo());
      final foreign = Directory(
        '${tmp.path}/${entry.hubDirName}/snapshots/9f2a1c',
      )..createSync(recursive: true);
      File('${foreign.path}/config.json').writeAsStringSync(configJson);

      // Removing the hub dir would destroy the foreign install too.
      expect(await installer.delete(entry), isFalse);
      expect(foreign.existsSync(), isTrue);
      expect(Directory(installer.snapshotPath(entry)).existsSync(), isTrue);
    });

    test('delete refuses an interrupted (marker-less) manager dir', () async {
      final tmp = await Directory.systemTemp.createTemp('mlx_installer_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final entry = mlxModelCatalog.first;
      final installer = MlxModelInstaller(hubRoot: tmp.path);
      final snapshotPath = installer.snapshotPath(entry);
      Directory(snapshotPath).createSync(recursive: true);
      File('$snapshotPath/config.json').writeAsStringSync(configJson);

      expect(await installer.delete(entry), isFalse);
      expect(Directory(snapshotPath).existsSync(), isTrue);
    });
  });
}
