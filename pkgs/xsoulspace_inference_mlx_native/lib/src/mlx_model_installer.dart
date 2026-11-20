import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'laya_native_decision_engine.dart';

import 'mlx_model_catalog.dart';

/// The stable snapshot directory name the manager installs into under a
/// repo's `snapshots/` (`models--<org>--<name>/snapshots/la-manager/`).
/// The Qwen3 discovery accepts ANY snapshot dir holding a `config.json`,
/// so the stable name needs no registry of its own.
const String mlxManagerSnapshotDirName = 'la-manager';

/// The marker file the manager writes into the snapshot dir at install
/// completion. Delete goes ONLY through this marker: a pre-existing
/// cache entry (installed by a terminal or another tool) is never
/// deletable through the manager.
const String mlxManagerMarkerFileName = '.installed-by-la-manager';

/// The base URL law for hub file resolution (design
/// `models-local-manager.md`).
const String _hubResolveBase = 'https://huggingface.co';

/// A named refusal. The install stream emits a `failed`
/// [ProvisionProgress] and then completes with this error carrying the
/// same [code].
///
/// Codes: `user_consent_required`, `network_blocked`,
/// `max_download_exceeded`, `install_in_progress`, and
/// `install_failed:<detail>` (IO errors, missing required files,
/// verification failures).
final class MlxModelInstallRefusal implements Exception {
  const MlxModelInstallRefusal(this.code, [this.detail]);

  /// The named refusal code (`install_failed:<detail>` embeds the
  /// detail in the code itself).
  final String code;

  /// Optional human context (URLs, byte counts).
  final String? detail;

  @override
  String toString() => detail == null
      ? 'MlxModelInstallRefusal: $code'
      : 'MlxModelInstallRefusal: $code ($detail)';
}

/// Whether a catalog entry is already present in the hub cache.
final class InstalledState {
  const InstalledState({required this.installed, this.snapshotDir});

  const InstalledState.notInstalled() : installed = false, snapshotDir = null;

  /// True when a snapshot dir with a `config.json` exists under the
  /// entry's hub dir (the same law the Qwen3 discovery applies).
  final bool installed;

  /// The discovered snapshot dir, when [installed].
  final String? snapshotDir;
}

/// One opened remote model file.
///
/// When [resumeOffset] is non-null the server honored the Range request
/// and [body] starts exactly at that byte — [contentLength] is then the
/// REMAINING length, not the full file size.
final class MlxRemoteModelFile {
  const MlxRemoteModelFile({
    required this.body,
    this.contentLength,
    this.resumeOffset,
  });

  /// The file's byte stream (the response body).
  final Stream<List<int>> body;

  /// Total body length in bytes (HTTP Content-Length), or null when the
  /// server sent no length (chunked).
  final int? contentLength;

  /// The byte offset [body] starts at when a Range request was honored;
  /// null for a full body.
  final int? resumeOffset;
}

/// Opens one remote file of a catalog repo. Returning null names a 404
/// (the file does not exist at [url]) — required files refuse, optional
/// files skip honestly. [resumeOffset] asks the server for the body from
/// that byte (HTTP Range).
typedef MlxModelFileOpener = Future<MlxRemoteModelFile?> Function(
  Uri url, {
  int? resumeOffset,
});

/// The default HTTPS opener for hub resolve URLs (dart:io `HttpClient`).
///
/// Owns one client for the whole install run; the installer closes it
/// when it created this opener itself, otherwise the caller owns
/// [close].
final class MlxHttpModelFileOpener {
  MlxHttpModelFileOpener({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Releases the underlying client (open connections drain).
  void close() => _client.close();

  Future<MlxRemoteModelFile?> call(Uri url, {int? resumeOffset}) async {
    final request = await _client.getUrl(url);
    if (resumeOffset != null && resumeOffset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeOffset-');
    }
    final response = await request.close();
    final status = response.statusCode;
    if (status == 404) {
      try {
        await response.drain<void>();
      } catch (_) {}
      return null;
    }
    if (status != 200 && status != 206) {
      try {
        await response.drain<void>();
      } catch (_) {}
      throw MlxModelInstallRefusal(
        'install_failed:http_$status',
        'GET $url failed',
      );
    }
    final honored = status == 206 && resumeOffset != null && resumeOffset > 0;
    return MlxRemoteModelFile(
      body: response,
      contentLength: response.contentLength >= 0
          ? response.contentLength
          : null,
      resumeOffset: honored ? resumeOffset : null,
    );
  }
}

/// One file the install run will transfer.
final class _PlannedFile {
  const _PlannedFile(
    this.name,
    this.contentLength, {
    required this.isRequired,
    this.isWeights = false,
  });

  final String name;
  final int? contentLength;
  final bool isRequired;
  final bool isWeights;
}

/// The hub-cache installer — the explicit-user-action exception to the
/// runtime's never-download law.
///
/// Installs land in the SAME `models--<org>--<name>/snapshots/` layout
/// the Qwen3 discovery scans, so an installed model needs no second
/// registry: it appears wherever [listCachedQwen3Snapshots] is read.
///
/// Laws:
/// - no byte moves without `userConsent: true` (the UI names the size
///   first); the network gate hook stays available for Wi-Fi-only
///   policy;
/// - the byte budget (`maxDownloadBytes`) is checked against summed
///   Content-Lengths BEFORE any download starts;
/// - interrupted installs resume from `<file>.part` via HTTP Range; a
///   completed-size file is kept;
/// - the marker [mlxManagerMarkerFileName] is written at completion and
///   [delete] refuses without it.
final class MlxModelInstaller {
  MlxModelInstaller({
    this.hubRoot,
    this.maxDownloadBytes,
    this.isNetworkAllowed,
    this.fileOpener,
  });

  /// Hub root override (tests). Null → `$HOME/.cache/huggingface/hub`,
  /// the same root the discovery defaults to.
  final String? hubRoot;

  /// The pre-flight byte budget. Null → no limit.
  final int? maxDownloadBytes;

  /// Network gate hook (e.g. a Wi-Fi-only policy). Returning false
  /// refuses with `network_blocked` before anything runs. Null → the
  /// network is allowed.
  final bool Function()? isNetworkAllowed;

  /// The file opener seam. Null → the default HTTPS opener against
  /// `https://huggingface.co/<repo>/resolve/main/<file>`. Injected
  /// (typically in tests) to serve a canned in-memory repo map with zero
  /// network.
  final MlxModelFileOpener? fileOpener;

  final Set<String> _inflight = <String>{};

  /// Where a repo's files land: `<hubRoot>/<entry.hubDirName>/snapshots/la-manager`.
  String snapshotPath(MlxModelCatalogEntry entry) =>
      '${_hubRootOrThrow()}/${entry.hubDirName}/snapshots/$mlxManagerSnapshotDirName';

  /// Whether the entry is already installed (a snapshot dir with a
  /// `config.json` under its hub dir — the discovery's own law).
  InstalledState stateOf(MlxModelCatalogEntry entry) {
    final root = _hubRootOrNull();
    if (root == null) return const InstalledState.notInstalled();
    final dir = _installedSnapshotDir('$root/${entry.hubDirName}');
    return dir == null
        ? const InstalledState.notInstalled()
        : InstalledState(installed: true, snapshotDir: dir);
  }

  /// Installs [entry] into the hub cache.
  ///
  /// A single-subscription stream of [ProvisionProgress]: `checking`
  /// (resolving the file list + sizes) → `downloading` (percent over the
  /// WHOLE byte total, Content-Length summed) → `loading` (verification:
  /// config.json parses, weights non-empty) → `ready`. Refusals emit a
  /// `failed` progress and then complete the stream with an
  /// [MlxModelInstallRefusal] carrying the named code. Already-installed
  /// entries short-circuit to `ready` without touching the network.
  Stream<ProvisionProgress> install(
    MlxModelCatalogEntry entry, {
    required bool userConsent,
  }) {
    var done = false;
    var cancelled = false;
    late final StreamController<ProvisionProgress> controller;
    controller = StreamController<ProvisionProgress>(
      onCancel: () => cancelled = true,
      onListen: () async {
        void emit(
          ProvisionPhase phase,
          String message, {
          int? percent,
          int? downloadedBytes,
          int? totalBytes,
        }) => controller.add(
          ProvisionProgress(
            phase: phase,
            message: message,
            percent: percent,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );

        void fail(String code, [String? detail]) {
          if (done) return;
          done = true;
          emit(ProvisionPhase.failed, detail == null ? code : '$code: $detail');
          controller
            ..addError(MlxModelInstallRefusal(code, detail))
            ..close();
        }

        try {
          // 1. Hard refusals BEFORE anything is created — consent refusal
          // touches no bytes and no paths.
          if (!userConsent) {
            throw const MlxModelInstallRefusal(
              'user_consent_required',
              'the UI must name the size and get explicit consent first',
            );
          }
          if (isNetworkAllowed != null && !isNetworkAllowed!()) {
            throw const MlxModelInstallRefusal(
              'network_blocked',
              'the network gate returned false',
            );
          }
          if (!_inflight.add(entry.repoId)) {
            throw MlxModelInstallRefusal(
              'install_in_progress',
              'an install of ${entry.repoId} is already running',
            );
          }
          final hubDirPath = '${_hubRootOrThrow()}/${entry.hubDirName}';
          emit(ProvisionPhase.checking, 'resolving ${entry.hubDirName}');

          // 2. Already installed? Short-circuit honestly (idempotent).
          final existing = _installedSnapshotDir(hubDirPath);
          if (existing != null) {
            done = true;
            emit(
              ProvisionPhase.ready,
              'already installed at $existing',
              percent: 100,
            );
            controller.close();
            return;
          }
          final snapshotDirPath =
              '$hubDirPath/snapshots/$mlxManagerSnapshotDirName';

          final ownedOpener = fileOpener == null
              ? MlxHttpModelFileOpener()
              : null;
          final open = fileOpener ?? ownedOpener!.call;
          try {
            // 3. checking — resolve the concrete file plan.
            final plan = <_PlannedFile>[];
            Future<MlxRemoteModelFile?> openFile(String name) async {
              emit(ProvisionPhase.checking, 'resolving $name');
              return open(_resolveUrl(entry, name));
            }

            void refuseMissing(_PlannedFile file) =>
                throw MlxModelInstallRefusal(
                  'install_failed:${file.name}',
                  'required file missing (404) at '
                      '${_resolveUrl(entry, file.name)}',
                );

            for (final name in entry.requiredFiles) {
              final f = await openFile(name);
              if (f == null) {
                refuseMissing(_PlannedFile(name, null, isRequired: true));
              }
              plan.add(_PlannedFile(name, f!.contentLength, isRequired: true));
              await _discard(f);
            }
            for (final name in entry.optionalFiles) {
              final f = await openFile(name);
              if (f == null) continue; // skipped honestly
              plan.add(_PlannedFile(name, f.contentLength, isRequired: false));
              await _discard(f);
            }
            // Weights: a single model.safetensors, else the sharded index
            // plus every shard its weight_map names.
            const singleWeights = 'model.safetensors';
            final single = await openFile(singleWeights);
            if (single != null) {
              plan.add(
                _PlannedFile(
                  singleWeights,
                  single.contentLength,
                  isRequired: true,
                  isWeights: true,
                ),
              );
              await _discard(single);
            } else {
              const indexName = 'model.safetensors.index.json';
              final index = await openFile(indexName);
              if (index == null) {
                throw MlxModelInstallRefusal(
                  'install_failed:$singleWeights',
                  'no weights found in ${entry.repoId} (404 on '
                      '$singleWeights and $indexName)',
                );
              }
              plan.add(
                _PlannedFile(
                  indexName,
                  index.contentLength,
                  isRequired: true,
                  isWeights: true,
                ),
              );
              final shards = _weightMapShards(await _collectBytes(index.body));
              for (final shard in shards) {
                final s = await openFile(shard);
                if (s == null) {
                  refuseMissing(_PlannedFile(shard, null, isRequired: true));
                }
                plan.add(
                  _PlannedFile(
                    shard,
                    s!.contentLength,
                    isRequired: true,
                    isWeights: true,
                  ),
                );
                await _discard(s);
              }
            }

            // 4. Byte budget BEFORE any download starts.
            final totalBytes = plan.fold<int>(
              0,
              (sum, f) =>
                  f.contentLength == null ? sum : sum + f.contentLength!,
            );
            final anyUnknownLength = plan.any((f) => f.contentLength == null);
            if (maxDownloadBytes != null &&
                !anyUnknownLength &&
                totalBytes > maxDownloadBytes!) {
              throw MlxModelInstallRefusal(
                'max_download_exceeded',
                'install needs ${_megabytes(totalBytes)} MB, the limit is '
                    '${_megabytes(maxDownloadBytes!)} MB',
              );
            }

            // 5. downloading — per-file parts renamed into place,
            // progress percent over the whole byte total.
            Directory(snapshotDirPath).createSync(recursive: true);
            var completedBytes = 0; // files finalized so far
            var runBytes = 0; // transfer of the file in flight
            var transferredRun = 0; // everything this run moved
            var lastPercent = -1;
            void emitDownloading({bool force = false}) {
              final done_ = completedBytes + runBytes;
              final percent = totalBytes > 0
                  ? ((done_ * 100) ~/ totalBytes).clamp(0, 100)
                  : null;
              if (!force && percent == lastPercent) return;
              lastPercent = percent ?? -1;
              emit(
                ProvisionPhase.downloading,
                'downloading ${entry.repoName}',
                percent: percent,
                downloadedBytes: done_,
                totalBytes: totalBytes > 0 ? totalBytes : null,
              );
            }

            emitDownloading(force: true);
            for (final f in plan) {
              runBytes = 0;
              // ADR — the ATTEMPT LOOP (2026-11-18, the live dogfood's
              // stuck-at-38% lesson): a CDN connection that dies
              // mid-body surfaces as `read_idle`/`http_*` — TRANSIENT
              // by nature, and the part on disk holds every byte
              // already fetched. Retry in place (resume from the part)
              // instead of failing the whole install; consented bytes
              // already flowed, so no re-consent is needed.
              var attempts = 0;
              while (true) {
                attempts++;
                try {
                  await _downloadPlanned(
                    entry,
                    f,
                    Directory(snapshotDirPath),
                    open,
                    onBytes: (n) {
                      runBytes += n;
                      transferredRun += n;
                      if (maxDownloadBytes != null &&
                          transferredRun > maxDownloadBytes!) {
                        throw MlxModelInstallRefusal(
                          'max_download_exceeded',
                          'transferred ${_megabytes(transferredRun)} MB this '
                              'run, the limit is '
                              '${_megabytes(maxDownloadBytes!)} MB '
                              '(lengths unknown ahead of time)',
                        );
                      }
                      emitDownloading();
                    },
                  );
                } on MlxModelInstallRefusal catch (refusal) {
                  // Transient connection deaths resume IN PLACE — the
                  // part on disk holds every byte already fetched;
                  // re-consent is not needed. The shapes (2026-11-20
                  // validation findings, one per live run): the read-idle
                  // guard's own code, CDN HTTP statuses, and dart:io
                  // network deaths wrapped by the file-named refusal —
                  // `HttpException: Connection closed` mid-body AND
                  // `SocketException: Operation timed out` on the hub
                  // itself. None of these is permanent by nature; the
                  // permanent file-named refusals (404 missing, failed
                  // verification) carry none of these markers.
                  final detail = refusal.detail ?? '';
                  final transientNetwork = detail.contains('HttpException') ||
                      detail.contains('SocketException') ||
                      detail.contains('Connection closed') ||
                      detail.contains('Connection reset') ||
                      detail.contains('timed out');
                  final transient =
                      refusal.code == 'install_failed:read_idle' ||
                      refusal.code.startsWith('install_failed:http_') ||
                      (refusal.code.startsWith('install_failed:') &&
                          transientNetwork);
                  if (!transient || attempts >= 4 || cancelled) rethrow;
                  await Future<void>.delayed(Duration(seconds: 2 * attempts));
                  continue;
                }
                final part = File('$snapshotDirPath/${f.name}');
                completedBytes += part.existsSync()
                    ? part.lengthSync()
                    : (f.contentLength ?? 0);
                emitDownloading(force: true);
                if (cancelled) throw const MlxModelInstallCancel();
                break; // the file is complete — the next planned file
              }
            }

            // 6. loading — post-download verification.
            emit(ProvisionPhase.loading, 'verifying');
            _verify(plan, snapshotDirPath);

            // 7. ready — write the manager marker LAST (install complete).
            File('$snapshotDirPath/$mlxManagerMarkerFileName')
                .writeAsStringSync(
                  'installed by the last_answer model manager '
                  '${DateTime.now().toIso8601String()}\n'
                  'delete only through MlxModelInstaller.delete\n',
                );
            done = true;
            emit(
              ProvisionPhase.ready,
              'installed at $snapshotDirPath',
              percent: 100,
              downloadedBytes: totalBytes > 0 ? totalBytes : null,
              totalBytes: totalBytes > 0 ? totalBytes : null,
            );
            controller.close();
          } finally {
            ownedOpener?.close();
          }
        } on MlxModelInstallCancel {
          done = true;
          controller.close();
        } on MlxModelInstallRefusal catch (e) {
          fail(e.code, e.detail);
        } catch (e) {
          fail('install_failed:${e.runtimeType}', e.toString());
        } finally {
          _inflight.remove(entry.repoId);
        }
      },
    );
    return controller.stream;
  }

  /// Deletes the entry's hub dir — ONLY when the manager's marker file
  /// exists in its own snapshot (the entry was installed by this
  /// manager) and no foreign complete snapshot shares the hub dir.
  /// Returns false honestly otherwise: a pre-existing cache entry
  /// installed by a terminal or another tool is never deletable here.
  Future<bool> delete(MlxModelCatalogEntry entry) async {
    final root = _hubRootOrNull();
    if (root == null) return false;
    final hubDir = Directory('$root/${entry.hubDirName}');
    if (!hubDir.existsSync()) return false;
    final snapshots = Directory('${hubDir.path}/snapshots');
    if (!snapshots.existsSync()) return false;
    final managerDirPath = '${snapshots.path}/$mlxManagerSnapshotDirName';
    if (!File('$managerDirPath/$mlxManagerMarkerFileName').existsSync()) {
      return false;
    }
    for (final dir in snapshots.listSync().whereType<Directory>()) {
      if (dir.path == managerDirPath) continue;
      if (File('${dir.path}/config.json').existsSync()) {
        return false; // deleting the hub dir would destroy a foreign install
      }
    }
    try {
      await hubDir.delete(recursive: true);
    } on FileSystemException {
      return false;
    }
    return true;
  }

  String? _hubRootOrNull() => hubRoot ?? _defaultHubRoot();

  String _hubRootOrThrow() {
    final root = _hubRootOrNull();
    if (root != null) return root;
    throw const MlxModelInstallRefusal(
      'install_failed:no_home_directory',
      'HOME is not set; pass hubRoot explicitly',
    );
  }

  static String? _defaultHubRoot() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/.cache/huggingface/hub';
  }

  static Uri _resolveUrl(MlxModelCatalogEntry entry, String fileName) =>
      Uri.parse('$_hubResolveBase/${entry.repoId}/resolve/main/$fileName');

  /// The first COMPLETE snapshot dir under a hub dir, the manager's own
  /// stable dir preferred, else the first sorted match — the same law
  /// the Qwen3 discovery applies (any snapshot with a config.json
  /// qualifies), with one refinement: the manager's own dir must also
  /// carry the completion marker and a weights artifact, so an install
  /// interrupted after config.json landed reports NOT installed and the
  /// next install resumes it instead of lying ready.
  static String? _installedSnapshotDir(String hubDirPath) {
    final snapshots = Directory('$hubDirPath/snapshots');
    if (!snapshots.existsSync()) return null;
    final dirs =
        snapshots.listSync().whereType<Directory>().map((d) => d.path).toList()
          ..sort();
    String? fallback;
    for (final path in dirs) {
      if (!_snapshotComplete(path)) continue;
      if (path.endsWith('/$mlxManagerSnapshotDirName')) return path;
      fallback ??= path;
    }
    return fallback;
  }

  /// A foreign snapshot (any hash dir) is complete when it holds a
  /// `config.json` AND its weights resolve — the discovery's
  /// dangling-blob law (2026-11-18): a config-only dir whose weight
  /// symlinks dangle (the wiped shared-blob store) must report NOT
  /// installed, or the row offers a load that can only fail. The
  /// manager-owned `la-manager` dir additionally needs the marker
  /// ([mlxManagerMarkerFileName] is written at verified install
  /// completion, never before).
  static bool _snapshotComplete(String dirPath) {
    if (!File('$dirPath/config.json').existsSync()) return false;
    final managerOwned = dirPath.endsWith('/$mlxManagerSnapshotDirName');
    if (!managerOwned) return qwenSnapshotWeightsResolve(dirPath);
    return File('$dirPath/$mlxManagerMarkerFileName').existsSync() &&
        (File('$dirPath/model.safetensors').existsSync() ||
            File('$dirPath/model.safetensors.index.json').existsSync());
  }

  /// Probing discards a body without consuming it (canceling an
  /// un-read HTTP response aborts the connection instead of draining
  /// gigabytes).
  static Future<void> _discard(MlxRemoteModelFile file) async {
    final sub = file.body.listen((_) {});
    try {
      await sub.cancel();
    } catch (_) {}
  }

  static Future<List<int>> _collectBytes(Stream<List<int>> body) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Parses `weight_map` out of a sharded-weights index and returns the
  /// deduped, sorted shard file names.
  static List<String> _weightMapShards(List<int> indexBytes) {
    const name = 'model.safetensors.index.json';
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(indexBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw MlxModelInstallRefusal(
        'install_failed:$name',
        'downloaded index does not parse: $e',
      );
    }
    final weightMap = json['weight_map'];
    if (weightMap is! Map) {
      throw MlxModelInstallRefusal(
        'install_failed:$name',
        'the index has no weight_map',
      );
    }
    final shards = weightMap.values.whereType<String>().toSet().toList()
      ..sort();
    if (shards.isEmpty) {
      throw MlxModelInstallRefusal(
        'install_failed:$name',
        'the weight_map names no shards',
      );
    }
    return shards;
  }

  Future<void> _downloadPlanned(
    MlxModelCatalogEntry entry,
    _PlannedFile file,
    Directory snapshotDir,
    MlxModelFileOpener open, {
    required void Function(int byteCount) onBytes,
  }) async {
    final destPath = '${snapshotDir.path}/${file.name}';
    final dest = File(destPath);
    final part = File('$destPath.part');
    if (dest.existsSync()) {
      final len = dest.lengthSync();
      if (file.contentLength == null || len == file.contentLength) {
        return; // already complete — kept
      }
      dest.deleteSync(); // stray truncated file — refetch honestly
    }
    var offset = 0;
    if (part.existsSync()) {
      offset = part.lengthSync();
      if (file.contentLength != null && offset >= file.contentLength!) {
        part.renameSync(destPath); // the part already holds the whole file
        return;
      }
    }
    MlxRemoteModelFile? remote;
    var resumed = false;
    if (offset > 0) {
      remote = await open(_resolveUrl(entry, file.name), resumeOffset: offset);
      if (remote != null && remote.resumeOffset == offset) resumed = true;
    }
    remote ??= await open(_resolveUrl(entry, file.name));
    if (remote == null) {
      if (part.existsSync() && !resumed) part.deleteSync();
      if (file.isRequired) {
        throw MlxModelInstallRefusal(
          'install_failed:${file.name}',
          'required file missing (404) at ${_resolveUrl(entry, file.name)}',
        );
      }
      return; // optional file skipped honestly
    }
    IOSink? sink;
    try {
      sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      // The READ-IDLE GUARD (2026-11-18, the live dogfood's stuck-at-38%
      // lesson): a CDN connection that dies mid-body silences the stream
      // forever — bare `await for` would hang the install with no error
      // and no resume. 60s without a chunk raises a named refusal; the
      // part stays on disk and the outer attempt loop RESUMES from it.
      await for (final chunk in remote.body.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) => sink.addError(
          const MlxModelInstallRefusal(
            'install_failed:read_idle',
            'no bytes for 60s — the connection died mid-body',
          ),
        ),
      )) {
        sink.add(chunk);
        onBytes(chunk.length);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      final got = part.lengthSync();
      if (file.contentLength != null && got != file.contentLength) {
        throw MlxModelInstallRefusal(
          'install_failed:${file.name}',
          'transferred $got bytes but Content-Length was '
              '${file.contentLength}',
        );
      }
      part.renameSync(destPath);
    } on MlxModelInstallRefusal {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      rethrow; // the part stays on disk — the next install resumes it
    } on MlxModelInstallCancel {
      try {
        await sink?.close();
      } catch (_) {}
      rethrow; // cancelled mid-file — the part stays on disk for resume
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      throw MlxModelInstallRefusal('install_failed:${file.name}', e.toString());
    }
  }

  void _verify(List<_PlannedFile> plan, String snapshotDirPath) {
    final configFile = File('$snapshotDirPath/config.json');
    if (!configFile.existsSync() || configFile.lengthSync() == 0) {
      throw const MlxModelInstallRefusal(
        'install_failed:verification',
        'config.json missing or empty after download',
      );
    }
    try {
      jsonDecode(configFile.readAsStringSync());
    } catch (e) {
      throw MlxModelInstallRefusal(
        'install_failed:verification',
        'config.json does not parse: $e',
      );
    }
    for (final f in plan) {
      if (!f.isWeights) continue;
      final weights = File('$snapshotDirPath/${f.name}');
      if (!weights.existsSync() || weights.lengthSync() == 0) {
        throw MlxModelInstallRefusal(
          'install_failed:verification',
          '${f.name} missing or empty after download',
        );
      }
    }
  }

  static int _megabytes(int bytes) => (bytes / (1024 * 1024)).round();
}

/// Internal: the listening side cancelled mid-download. The in-flight
/// `.part` file stays on disk so the next install resumes it.
final class MlxModelInstallCancel implements Exception {
  const MlxModelInstallCancel();
}
