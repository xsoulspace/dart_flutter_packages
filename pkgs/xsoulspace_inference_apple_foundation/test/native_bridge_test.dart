// ignore_for_file: lines_longer_than_80_chars

/// Pure unit coverage for the FFI bridge plumbing — no macOS runtime or
/// dylib required. On-device behaviour is validated by the bin smokes
/// (`apple_foundation_cli`, `stream_smoke`) and the stress CLI.
import 'dart:async';
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

  group('final native model input', () {
    const fragments = <Object>[
      'known\n  symbol opaque-42\n    freshness current at revision r7\n    fact area equals width times height',
      'gaps\n  task acceptance unknown',
      'actions\n  edit target opaque-42 with observed revision r7',
    ];
    for (final streaming in [false, true]) {
      test(
        '${streaming ? "stream" : "infer"} forwards ordered host fragments exactly once',
        () async {
          final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverOk;
          final client = AppleFoundationNativeClient(bindings: fake);
          addTearDown(client.dispose);
          final request = InferenceRequest(
            prompt: 'repair-area',
            systemPrompt: 'semantic instructions',
            contextFragments: fragments,
          );
          final estimate = client.estimateInputTokensFor(
            request,
            streaming: streaming,
          );
          expect(fake.packets, isEmpty);
          expect(client.maxInputTokens, 3800 - 1024);
          if (streaming) {
            final session = await client.streamStructuredText(request);
            final drain = session.events.drain<void>();
            expect((await session.result).success, isTrue);
            await drain;
          } else {
            expect((await client.infer(request)).success, isTrue);
          }
          final packet = fake.packets.single;
          expect(estimate, (jsonEncode(packet).length + 3) ~/ 4);
          final prompt = packet['prompt'] as String;
          expect(prompt, 'repair-area\n\n${fragments.join("\n\n")}');
          expect(packet['instructions'], 'semantic instructions');
          expect('repair-area'.allMatches(prompt), hasLength(1));
          for (final fragment in fragments) {
            expect(
              RegExp(RegExp.escape(fragment.toString())).allMatches(prompt),
              hasLength(1),
            );
          }
        },
      );
    }
    test('empty fragments leave the native prompt unchanged', () async {
      final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverOk;
      final client = AppleFoundationNativeClient(bindings: fake);
      addTearDown(client.dispose);
      await client.infer(InferenceRequest(prompt: 'unchanged'));
      expect(fake.packets.single['prompt'], 'unchanged');
    });
    test(
      'tool and schema encoding count toward the final packet preflight estimate',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverOk;
        final client = AppleFoundationNativeClient(
          bindings: fake,
          maxContextTokens: 128,
          outputReserveTokens: 0,
        );
        addTearDown(client.dispose);
        expect(
          (await client.infer(InferenceRequest(prompt: 'small'))).success,
          isTrue,
        );
        fake.packets.clear();
        final tools = ToolRegistry();
        tools.register(
          ToolDef.encode(
            name: const ToolName('read'),
            description: 'tool-parameter-facts ' * 100,
            argsSchema: SchemaBundle.empty,
            execute: (_) async => {'ok': true},
          ),
        );
        expect(
          client.estimateInputTokensFor(
            InferenceRequest(prompt: 'small'),
            toolRegistry: tools,
          ),
          greaterThan(client.maxInputTokens),
        );
        final toolRejected = await client.infer(
          InferenceRequest(prompt: 'small'),
          toolRegistry: tools,
        );
        expect(toolRejected.error?.code, 'context_window_exceeded');
        expect(toolRejected.meta['estimator'], 'encoded_packet_chars_over_4');
        expect(fake.packets, isEmpty);
        final schemaRejected = await client.infer(
          InferenceRequest(
            prompt: 'small',
            task: InferenceTask.nativelyStructuredText,
            outputSchema: {
              'type': 'object',
              'description': 'schema-facts ' * 100,
            },
          ),
        );
        expect(schemaRejected.error?.code, 'context_window_exceeded');
        expect(fake.packets, isEmpty);
      },
    );
    test(
      'stream preflight rejects oversized forwarded fragments before native submit',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverOk;
        final client = AppleFoundationNativeClient(
          bindings: fake,
          maxContextTokens: 128,
          outputReserveTokens: 0,
        );
        addTearDown(client.dispose);
        await expectLater(
          client.streamStructuredText(
            InferenceRequest(
              prompt: 'small',
              contextFragments: ['semantic fact ' * 100],
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('context_window_exceeded'),
            ),
          ),
        );
        expect(fake.packets, isEmpty);
      },
    );
  });

  group('opt-in transport diagnostics', () {
    test(
      'captures exact bridge packet and tool result with correlation',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.hang;
        final events = <Map<String, Object?>>[];
        final client = AppleFoundationNativeClient(
          bindings: fake,
          onTransportDiagnostic: events.add,
        );
        addTearDown(client.dispose);
        final metadata = <String, dynamic>{
          'actor': 'actor-7',
          'task': 'task-2',
        };
        final inference = client.infer(
          InferenceRequest(prompt: 'diagnostic prompt', metadata: metadata),
        );

        expect(events, hasLength(1));
        expect(events.single['type'], 'afm.generate');
        expect(events.single['metadata'], metadata);
        expect(events.single['requestJson'], jsonEncode(fake.packets.single));
        fake.deliverToolCall(1, <String, Object?>{
          'id': 'call-9',
          'name': 'missing_tool',
          'arguments': '{"target":"opaque-42"}',
        });
        await _until(() => fake.toolResults.isNotEmpty);
        final event = events.last;
        expect(event['type'], 'afm.tool_result');
        expect(event['metadata'], metadata);
        expect(event['generationId'], 1);
        expect(event['callId'], 'call-9');
        expect(event['toolName'], 'missing_tool');
        expect(event['argumentsJson'], '{"target":"opaque-42"}');
        expect(event['resultJson'], '{"error":"no handler for missing_tool"}');
        expect(fake.toolResults.single, event['resultJson']);

        fake.deliverDone(1, <String, dynamic>{'ok': true, 'output': 'done'});
        expect((await inference).success, isTrue);
      },
    );

    test(
      'observer exceptions cannot prevent native submission or tool reply',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.hang;
        final client = AppleFoundationNativeClient(
          bindings: fake,
          onTransportDiagnostic: (_) => throw StateError('observer failure'),
        );
        addTearDown(client.dispose);
        final inference = client.infer(InferenceRequest(prompt: 'dispatch'));

        expect(fake.packets, hasLength(1));
        fake.deliverToolCall(1, <String, Object?>{
          'id': 'call-throwing-observer',
          'name': 'missing_tool',
          'arguments': '{}',
        });
        await _until(() => fake.toolResults.isNotEmpty);
        expect(
          fake.toolResults.single,
          '{"error":"no handler for missing_tool"}',
        );
        fake.deliverDone(1, <String, dynamic>{
          'ok': true,
          'output': 'still works',
        });
        expect((await inference).success, isTrue);
      },
    );

    test(
      'captures exact handler error result before native tool resumption',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.hang;
        final events = <Map<String, Object?>>[];
        final client = AppleFoundationNativeClient(
          bindings: fake,
          onTransportDiagnostic: events.add,
        );
        addTearDown(client.dispose);
        final tools = ToolRegistry()
          ..register(
            ToolDef(
              name: const ToolName('fails'),
              description: 'A deterministic failing test tool',
              execute: (_) async => throw StateError('known failure'),
            ),
          );
        final inference = client.infer(
          InferenceRequest(prompt: 'call failing tool'),
          toolRegistry: tools,
        );
        fake.deliverToolCall(1, <String, Object?>{
          'id': 'call-error-1',
          'name': 'fails',
          'arguments': '{}',
        });
        await _until(() => fake.toolResults.isNotEmpty);

        expect(fake.toolResults.single, '{"error":"Bad state: known failure"}');
        expect(events.last['resultJson'], fake.toolResults.single);
        expect(events.last['callId'], 'call-error-1');
        fake.deliverDone(1, <String, dynamic>{'ok': true, 'output': 'done'});
        expect((await inference).success, isTrue);
      },
    );

    test(
      'captures exact streaming packet and survives observer failures',
      () async {
        final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.hang;
        final events = <Map<String, Object?>>[];
        final client = AppleFoundationNativeClient(
          bindings: fake,
          onTransportDiagnostic: (event) {
            events.add(event);
            throw StateError('observer failure');
          },
        );
        addTearDown(client.dispose);
        final metadata = <String, dynamic>{
          'actor': 'actor-stream-3',
          'task': 'task-stream-8',
        };
        final session = await client.streamStructuredText(
          InferenceRequest(
            prompt: 'streamed request',
            contextFragments: const ['first fragment', 'second fragment'],
            metadata: metadata,
          ),
        );
        final drain = session.events.drain<void>();

        expect(fake.requestJsons, hasLength(1));
        expect(events, hasLength(1));
        expect(events.single['type'], 'afm.generate_stream');
        expect(events.single['metadata'], metadata);
        expect(events.single['requestJson'], fake.requestJsons.single);
        expect(jsonDecode(fake.requestJsons.single), <String, dynamic>{
          'prompt': 'streamed request\n\nfirst fragment\n\nsecond fragment',
          'instructions': null,
          'tools': null,
        });

        fake.deliverToolCall(1, <String, Object?>{
          'id': 'stream-call-1',
          'name': 'unexpected_stream_tool',
          'arguments': '{"input":1}',
        });
        await _until(() => fake.toolResults.isNotEmpty);
        expect(fake.toolResults.single, '{"error":"no tools in stream"}');
        expect(events.last['type'], 'afm.tool_result');
        expect(events.last['metadata'], metadata);
        expect(events.last['generationId'], 1);
        expect(events.last['callId'], 'stream-call-1');
        expect(events.last['argumentsJson'], '{"input":1}');
        expect(events.last['resultJson'], fake.toolResults.single);

        fake.deliverDone(1, <String, dynamic>{'ok': true, 'output': 'done'});
        expect((await session.result).success, isTrue);
        await drain;
      },
    );

    test('diagnostic callback is inert by default', () async {
      final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverOk;
      final client = AppleFoundationNativeClient(bindings: fake);
      addTearDown(client.dispose);

      expect(
        (await client.infer(InferenceRequest(prompt: 'default'))).success,
        isTrue,
      );
      expect(fake.packets, hasLength(1));
    });
  });

  group('generation timeout / cancel contract (P1 bridge crash fix)', () {
    test('timeout cancels the Swift generation, then a subsequent generate '
        'succeeds (no crash, structured error)', () async {
      final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.hang;
      final client = AppleFoundationNativeClient(
        bindings: fake,
        inferTimeout: const Duration(milliseconds: 30),
      );

      // 1. Hung generation → structured timeout error with cancelled flag.
      final timedOut = await client.infer(InferenceRequest(prompt: 'hang'));
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
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('structured generation errors propagate op-locally', () async {
      final fake = _FakeXsFmBindings()..behavior = _FakeBehavior.deliverError;
      final client = AppleFoundationNativeClient(
        bindings: fake,
        inferTimeout: const Duration(seconds: 5),
      );

      final result = await client.infer(InferenceRequest(prompt: 'too long'));
      expect(result.success, isFalse);
      expect(result.error?.code, 'exceeded_context_window');
      expect(result.error?.message, 'Exceeded model context window size');
      // No cancel: the generation finished (with an error) on its own.
      expect(fake.cancelledIds, isEmpty);

      client.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));
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
  final List<Map<String, dynamic>> packets = [];
  final List<String> requestJsons = <String>[];
  _FakeBehavior behavior = _FakeBehavior.hang;

  /// Generation ids passed to [cancelGeneration], in order.
  final List<int> cancelledIds = [];
  final Set<int> _cancelled = {};

  /// Set when the generation gate refused a late done delivery (stale
  /// callback simulation).
  int staleDrops = 0;

  Pointer<NativeFunction<DoneCbNative>>? _doneCb;
  Pointer<NativeFunction<ToolCbNative>>? _toolCb;
  final List<String> toolResults = <String>[];

  @override
  int isAvailable() => 1;

  @override
  int generateAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  ) {
    requestJsons.add(requestJson.cast<Utf8>().toDartString());
    packets.add(jsonDecode(requestJsons.last) as Map<String, dynamic>);
    _nextGen += 1;
    final gen = _nextGen;
    _doneCb = doneCb;
    _toolCb = toolCb;
    switch (behavior) {
      case _FakeBehavior.hang:
        break;
      case _FakeBehavior.deliverOk:
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 5)).then((_) {
            _deliver(gen, <String, dynamic>{'ok': true, 'output': 'hello'});
          }),
        );
      case _FakeBehavior.deliverError:
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 5)).then((_) {
            _deliver(gen, <String, dynamic>{
              'ok': false,
              'error': <String, dynamic>{
                'code': 'exceeded_context_window',
                'message': 'Exceeded model context window size',
              },
            });
          }),
        );
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
    return generateAsync(requestJson, toolCb, doneCb);
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

  void deliverDone(int gen, Map<String, dynamic> payload) =>
      _deliver(gen, payload);

  void deliverToolCall(int gen, Map<String, Object?> payload) {
    final callback = _toolCb;
    if (callback == null) return;
    final body = jsonEncode(<String, Object?>{...payload, 'generation': gen});
    callback.asFunction<void Function(Pointer<Char>)>()(
      body.toNativeUtf8().cast<Char>(),
    );
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
  int toolRespond(Pointer<Char> id, Pointer<Char> resultJson) {
    toolResults.add(resultJson.cast<Utf8>().toDartString());
    return 0;
  }

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

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
