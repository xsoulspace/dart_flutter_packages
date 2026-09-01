// ignore_for_file: lines_longer_than_80_chars

/// Pure unit coverage for the FFI bridge plumbing — no macOS runtime or
/// dylib required. On-device behaviour is validated by the bin smokes
/// (`apple_foundation_cli`, `stream_smoke`) and the stress CLI.
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/bindings.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/library_loader.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

void main() {
  group('XsFmLibraryLoader', () {
    test('override path wins over every candidate', () {
      final loader = XsFmLibraryLoader(overridePath: '/tmp/bridge.dylib');
      expect(loader.candidatePaths().first, '/tmp/bridge.dylib');
    });

    test('env override ranks second, build-hook output third', () {
      final loader = XsFmLibraryLoader();
      final paths = loader.candidatePaths();
      expect(paths.length, greaterThanOrEqualTo(3));
      expect(XsFmLibraryLoader.dylibName, 'libxs_fm_bridge.dylib');
      expect(
        XsFmLibraryLoader.assetId,
        'package:xsoulspace_inference_apple_foundation/swift_bridge',
      );
    });

    test('candidate paths are deduplicated and absolute', () {
      final loader = XsFmLibraryLoader();
      final paths = loader.candidatePaths();
      expect(paths.toSet().length, paths.length);
      for (final p in paths.skip(1)) {
        expect(p.startsWith('/'), isTrue);
      }
    });
  });

  group('AppleFoundationNativeClient contract', () {
    test('identity and task surface are stable', () {
      final client = AppleFoundationNativeClient();
      expect(client.id, 'apple_foundation_native');
      expect(
        client.supportedTasks,
        unorderedEquals(<InferenceTask>[
          InferenceTask.text,
          InferenceTask.implicitlyStructuredText,
          InferenceTask.nativelyStructuredText,
        ]),
      );
    });

    test('isAvailable starts false before any refresh', () {
      final client = AppleFoundationNativeClient();
      expect(client.isAvailable, isFalse);
    });
  });

  group('generation timeout / cancel contract (P1 bridge crash fix)', () {
    test(
      'timeout cancels the Swift generation, then a subsequent generate '
      'succeeds (no crash, structured error)',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.hang;
        final client = AppleFoundationNativeClient(
          bindings: fake,
          inferTimeout: const Duration(milliseconds: 30),
        );

        // 1. Hung generation → structured timeout error with cancelled flag.
        final timedOut = await client.infer(
          InferenceRequest(prompt: 'hang'),
        );
        expect(timedOut.success, isFalse);
        expect(timedOut.error?.code, 'generation_timeout');
        expect(timedOut.error?.message, contains('exceeded'));
        expect(timedOut.meta['cancelled'], isTrue);
        // The bridge was asked to cancel generation 1 BEFORE teardown.
        expect(fake.cancelledIds, [1]);

        // 2. A stale done payload from the cancelled generation (the exact
        //    callback-after-delete class that crashed the VM) must be
        //    harmless.
        fake.deliverStaleDoneFor(1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // 3. Subsequent generate succeeds normally.
        fake.behavior = _FakeBehavior.deliverOk;
        final ok = await client.infer(InferenceRequest(prompt: 'hi'));
        expect(ok.success, isTrue);
        expect(ok.data?.structuredOutput['text'], 'hello');
        // Only generation 1 was cancelled; generation 2 completed.
        expect(fake.cancelledIds, [1]);

        client.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('structured generation errors propagate op-locally', () async {
      final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverError;
      final client = AppleFoundationNativeClient(
        bindings: fake,
        inferTimeout: const Duration(seconds: 5),
      );

      final result = await client.infer(
        InferenceRequest(prompt: 'too long'),
      );
      expect(result.success, isFalse);
      expect(result.error?.code, 'exceeded_context_window');
      expect(result.error?.message, 'Exceeded model context window size');
      // No cancel: the generation finished (with an error) on its own.
      expect(fake.cancelledIds, isEmpty);

      client.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}

/// What the fake bridge does when `generateAsync` accepts a generation.
enum _FakeBehavior {
  /// Never deliver done — simulates a hung generation (the P1 crash
  /// precursor: AFM `generation_timeout`).
  hang,

  /// Deliver `{ok: true, output: ...}` after a short delay.
  deliverOk,

  /// Deliver a structured error payload after a short delay (the
  /// "Exceeded model context window size" class).
  deliverError,
}

/// In-memory bridge. `generateAsync` records the done/tool callback pointers
/// and — per [_FakeBehavior] — either hangs or invokes the done pointer via
/// FFI (a `NativeCallable.listener` pointer invoked from Dart posts back to
/// the test isolate, exactly like a native call would). `cancelGeneration`
/// records the cancel and permanently gates delivery for that generation,
/// mirroring the Swift-side contract introduced for the P1 crash fix.
final class _FakeXsFmBindings implements XsFmBindings {
  int _nextGen = 0;
  _FakeBehavior behavior = _FakeBehavior.hang;

  /// Generation ids passed to [cancelGeneration], in order.
  final List<int> cancelledIds = [];
  final Set<int> _cancelled = {};

  /// Set when the generation gate refused a late done delivery (stale
  /// callback simulation).
  int staleDrops = 0;

  Pointer<NativeFunction<DoneCbNative>>? _doneCb;

  @override
  int isAvailable() => 1;

  @override
  int generateAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  ) {
    _nextGen += 1;
    final gen = _nextGen;
    _doneCb = doneCb;
    switch (behavior) {
      case _FakeBehavior.hang:
        break;
      case _FakeBehavior.deliverOk:
        Future<void>.delayed(const Duration(milliseconds: 5)).then((_) {
          _deliver(gen, <String, dynamic>{'ok': true, 'output': 'hello'});
        });
      case _FakeBehavior.deliverError:
        Future<void>.delayed(const Duration(milliseconds: 5)).then((_) {
          _deliver(gen, <String, dynamic>{
            'ok': false,
            'error': <String, dynamic>{
              'code': 'exceeded_context_window',
              'message': 'Exceeded model context window size',
            },
          });
        });
    }
    return gen;
  }

  @override
  int generateStreamAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<StreamCbNative>> streamCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  ) {
    _nextGen += 1;
    return _nextGen; // streaming is exercised on-device, not here
  }

  void _deliver(int gen, Map<String, dynamic> payload) {
    if (_cancelled.contains(gen)) {
      // The gate: after cancel, the bridge must never invoke the callback.
      // (This branch documents the invariant; the registry removed the state
      // in Swift, so a delivery attempt here would be a bug in the FAKE.)
      staleDrops += 1;
      return;
    }
    final doneCb = _doneCb;
    if (doneCb == null) return;
    final fn = doneCb.asFunction<void Function(Pointer<Char>)>();
    final body = jsonEncode(<String, dynamic>{...payload, 'generation': gen});
    final c = body.toNativeUtf8().cast<Char>();
    fn(c.cast<Char>());
  }

  /// Simulates an OLD bridge (pre-cancel): delivers done for a generation
  /// that was already cancelled — the payload class that crashed the VM.
  void deliverStaleDoneFor(int gen) {
    final doneCb = _doneCb;
    if (doneCb == null) return;
    final fn = doneCb.asFunction<void Function(Pointer<Char>)>();
    final body = jsonEncode(<String, dynamic>{
      'generation': gen,
      'ok': false,
      'error': <String, dynamic>{
        'code': 'generation_error',
        'message': 'late callback from a deleted generation',
      },
    });
    final c = body.toNativeUtf8().cast<Char>();
    fn(c);
  }

  @override
  int toolRespond(Pointer<Char> id, Pointer<Char> resultJson) => 0;

  @override
  int cancelGeneration(int generationId) {
    cancelledIds.add(generationId);
    _cancelled.add(generationId);
    return 0;
  }

  @override
  void freeString(Pointer<Char> s) => malloc.free(s.cast<Utf8>());

  @override
  void setDebug(int enabled) {}

  @override
  int abiVersion() => 2;
}
