import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The unified-interface binding (ADR 0058): a loaded native engine
/// answers `InferenceClient` with the bench's winning cell — template
/// render, EOS stop, clean answer text. Skips honestly when the dylib or
/// the cached snapshots are absent.
void main() {
  test('lfm2 cast: infer maps request → template+EOS → clean answer',
      () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadLfm2();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
    }
    addTearDown(client.dispose);

    expect(client.id, 'mlx_native_lfm2');
    expect(client.isAvailable, isTrue);
    expect(client.supportedTasks, contains(InferenceTask.text));

    final result = await client.infer(
      InferenceRequest(
        prompt: 'Reply with exactly one word: the sky color by day?',
        maxTokens: 24,
      ),
    );
    expect(result.success, isTrue, reason: '${result.error?.toJson()}');
    final answer = result.data!.rawOutput!;
    expect(answer, isNotEmpty);
    expect(answer.endsWith('<|im_end|>'), isFalse,
        reason: 'the EOS literal never rides the unified answer');
    expect(result.data!.meta['finish_reason'], 'stop');
    final usage = result.data!.meta['usage'] as Map<String, dynamic>;
    expect(usage['completion_tokens'], greaterThan(0));
    expect(
      (usage['completion_tokens'] as int) <= 24,
      isTrue,
      reason: 'the EOS stop must end before the cap on an answerable prompt',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('lfm2 cast: ToolRegistry renders into the template', () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadLfm2();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
    }
    addTearDown(client.dispose);

    final registry = ToolRegistry()
      ..register(
        const ToolDefinition(
          description: 'Look up current weather for a city',
        ).toDef(
          name: const ToolName('get_weather'),
          execute: (final args) async => '{}',
        ),
      );
    final result = await client.infer(
      InferenceRequest(prompt: 'What is the weather in Tokyo?', maxTokens: 64),
      toolRegistry: registry,
    );
    expect(result.success, isTrue, reason: '${result.error?.toJson()}');
    expect(result.data!.rawOutput, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('qwen cast: infer answers; ToolRegistry renders', () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadQwen();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(client.dispose);

    expect(client.id, 'mlx_native_qwen');
    final result = await client.infer(
      InferenceRequest(
        prompt: 'Reply with exactly one word: 2+2=?',
        maxTokens: 24,
      ),
    );
    expect(result.success, isTrue, reason: '${result.error?.toJson()}');
    expect(result.data!.rawOutput, isNotEmpty);

    final registry = ToolRegistry()
      ..register(
        const ToolDefinition(description: 'echo')
            .toDef(name: const ToolName('echo'), execute: (final a) async => ''),
      );
    final withTools = await client.infer(
      InferenceRequest(
        prompt: 'Call the only tool you have with no arguments.',
        maxTokens: 64,
      ),
      toolRegistry: registry,
    );
    expect(withTools.success, isTrue, reason: '${withTools.error?.toJson()}');
    expect(withTools.data!.rawOutput, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('temperature honesty + unsupported task + lifecycle', () async {
    final NativeLfm2TextEngine engine;
    try {
      engine = await NativeLfm2TextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
    }
    final client = MlxNativeTextClient.lfm2(engine);

    final greedy = await client.infer(
      InferenceRequest(prompt: 'x', maxTokens: 2, temperature: 0.7),
    );
    expect(greedy.success, isTrue);
    expect(greedy.warnings, hasLength(1),
        reason: 'greedy-only engines must warn, never silently pretend');

    final wrongTask = await client.infer(
      InferenceRequest.speechToText(
        audioInput: InferenceAudioInput(
          source: InferenceAudioSource.filePath,
          mimeType: 'audio/wav',
          filePath: '/dev/null',
        ),
      ),
    );
    expect(wrongTask.success, isFalse);
    expect(wrongTask.error!.code, 'unsupported_task');

    // Lifecycle: dispose marks the CLIENT unavailable; the injected
    // engine outlives it (its owner unloads it).
    final disposable = MlxNativeTextClient.lfm2(engine);
    expect(disposable.isAvailable, isTrue);
    disposable.dispose();
    expect(disposable.isAvailable, isFalse);
    final afterDispose = await disposable.infer(
      InferenceRequest(prompt: 'x', maxTokens: 2),
    );
    expect(afterDispose.success, isFalse);
    expect(afterDispose.error!.code, 'unavailable');
    expect(client.isAvailable, isTrue,
        reason: 'disposing one client must not touch the shared engine');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
