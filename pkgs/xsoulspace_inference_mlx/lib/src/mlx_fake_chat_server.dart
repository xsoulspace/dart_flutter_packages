import 'mlx_chat_wire.dart';
import 'mlx_chat_wire_server.dart';

export 'mlx_chat_wire.dart' show MlxChatEndpoint, MlxChatResult;

/// A pure-Dart OpenAI-compatible chat wire fake over the shared
/// [MlxChatWireServer] skeleton, driven by a [MlxScriptedEngine] — the
/// same wire `mlx_lm.server` or the native engine speaks, with no model
/// runtime. Deterministic engines keep clients, prompt builders, and draft
/// lanes testable with no weights.
final class FakeMlxChatServer extends MlxChatWireServer {
  FakeMlxChatServer({
    required MlxScriptedEngine engine,
    super.model = 'fake-mlx',
    super.apiKey,
    super.address,
    super.port,
  }) : super(completeRequest: (request) async => engine.answer(request));
}

/// The scripted generation seam of the pure-Dart chat fake: an engine
/// answers a decoded [MlxChatRequest]. Deterministic engines keep the whole
/// client path testable with no Python runtime and no model weights.
abstract interface class MlxScriptedEngine {
  MlxChatResult answer(final MlxChatRequest request);
}

/// Replays pinned completions in order; an unpinned request falls back to
/// the last pin (or the empty string). Mirrors the scripted-engine shape
/// the laya server uses.
final class ScriptedMlxChatEngine implements MlxScriptedEngine {
  ScriptedMlxChatEngine(final List<String> completions)
    : completions = List<String>.unmodifiable(completions);

  final List<String> completions;
  final List<MlxChatRequest> requests = <MlxChatRequest>[];
  var _cursor = 0;

  /// Clears the cursor so a fresh run replays from the start.
  void reset() => _cursor = 0;

  @override
  MlxChatResult answer(final MlxChatRequest request) {
    requests.add(request);
    final text = completions.isEmpty
        ? ''
        : completions[_cursor < completions.length - 1
              ? _cursor++
              : completions.length - 1];
    return MlxChatResult(
      text: text,
      finishReason: 'stop',
      resolvedModel: request.model,
      promptTokens: request.messages.fold<int>(
        0,
        (total, message) => total + message.content.length ~/ 4,
      ),
      completionTokens: text.length ~/ 4,
    );
  }
}
