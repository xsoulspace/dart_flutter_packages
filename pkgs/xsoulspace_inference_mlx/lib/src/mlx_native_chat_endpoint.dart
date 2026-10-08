import 'mlx_chat_wire.dart';
import 'mlx_native_text_engine.dart';

/// The native engine bound to the shared [MlxChatEndpoint] seam: an
/// in-process engine over mlx-swift-lm, shaped exactly like the loopback
/// HTTP endpoint. Consumers swap [HttpMlxChatEndpoint] (Python server,
/// any OpenAI-compatible server) for this with no other change — the
/// engine-policy swap ADR-0039 proposes, already expressible in code.
///
/// The native engine is single-flight; concurrent [complete] calls
/// serialize behind the native lock.
final class NativeMlxChatEndpoint implements MlxChatEndpoint {
  NativeMlxChatEndpoint(this.engine);

  final NativeMlxTextEngine engine;

  /// Loads the snapshot directory (HF checkout shape) and returns the
  /// endpoint. Throws a named error when the native asset or weights are
  /// absent.
  static Future<NativeMlxChatEndpoint> load(final String modelDir) async =>
      NativeMlxChatEndpoint(await NativeMlxTextEngine.load(modelDir));

  @override
  Future<MlxChatResult> complete(final MlxChatRequest request) async {
    final generation = await engine.generate(
      MlxNativeRequest(
        prompt: request.messages.lastOrNull?.content ?? '',
        system: request.messages
            .where((message) => message.role == 'system')
            .map((message) => message.content)
            .join('\n'),
        maxTokens: request.maxTokens ?? 320,
        temperature: request.temperature ?? 0.0,
        stop: request.stop,
        templateArgs: request.templateArgs,
      ),
    );
    return MlxChatResult(
      text: generation.text,
      finishReason: generation.stopReason,
      resolvedModel: 'mlx_text_native',
      promptTokens: generation.promptTokens,
      completionTokens: generation.completionTokens,
    );
  }

  @override
  Future<void> dispose() async {
    engine.unload();
  }
}
