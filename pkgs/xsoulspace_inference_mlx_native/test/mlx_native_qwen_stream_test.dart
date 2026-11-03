import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// Token streaming at the engine and at the wire. Bars frozen BEFORE any
/// run (the lane's law), 2026-10-28:
///
///   ST-G1  the streamed delta stream is TOKEN-EXACT to the completion
///          path: the same prompt's joined deltas (trimmed) equal the
///          solo wire text, and the streamed ids equal the solo
///          completion ids (one native decode loop — the parity gates'
///          law, lifted to the stream).
///   ST-G2  `"stream": true` at the chat wire serves OpenAI-style SSE:
///          concatenated content deltas (trimmed) equal the completion
///          answer, the final frame carries finish_reason `stop` + usage,
///          and the wire terminates with `data: [DONE]`.
///
/// Laws carried by the implementation (documented, not re-gated here):
/// streaming is a SOLO-path feature; the prefix pool is not consulted;
/// EOS literals never ride the wire; a dylib without the streaming ABI
/// degrades to the completion shape. Skips honestly when the dylib or the
/// cached snapshot is absent, or the streaming ABI is missing.
void main() {
  String powerLine() {
    try {
      final out = Process.runSync('pmset', ['-g', 'ps']).stdout as String;
      final lines = LineSplitter.split(out).toList();
      return lines.isEmpty ? 'power: unknown' : lines.last.trim();
    } on Object {
      return 'power: unknown';
    }
  }

  test('stream gate: deltas are token-exact to the completion path', () async {
    final NativeQwenTextEngine engine;
    try {
      engine = await NativeQwenTextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native qwen unavailable: $error');
    }
    addTearDown(engine.dispose);
    if (!engine.supportsStreaming) {
      return markTestSkipped('native dylib lacks the streaming ABI');
    }
    stdout.writeln('power: ${powerLine()}');

    const prompt =
        'Classify the text. Answer with exactly one of: allow, deny\n\n'
        'Text: The request asks to read one public file.\nAnswer:';
    const eosIds = <int>[151645, 151643]; // <|im_end|>, <|endoftext|>

    final solo = engine.generate(
      prompt: prompt,
      maxTokens: 32,
      stopOnEos: true,
      eosIds: eosIds,
    );
    final soloText = solo.text
        .replaceAll(RegExp(r'<\|im_end\|>$'), '')
        .replaceAll(RegExp(r'<\|endoftext|>$'), '')
        .trim();

    final streamedIds = <int>[];
    final streamedText = StringBuffer();
    var done = false;
    String? stopReason;
    await for (final delta in engine.generateStream(
      prompt: prompt,
      maxTokens: 32,
      stopOnEos: true,
      eosIds: eosIds,
    )) {
      streamedIds.addAll(delta.newIds);
      streamedText.write(delta.text);
      if (delta.done) {
        done = true;
        stopReason = delta.stopReason;
      }
    }

    // ST-G1: token-exact to the completion path.
    expect(done, isTrue, reason: 'the stream must terminate with a done event');
    expect(stopReason, anyOf('stop', 'max_tokens'),
        reason: 'a terminal stop reason is carried');
    expect(streamedIds, solo.ids.sublist(solo.promptIds.length),
        reason: 'ST-G1: streamed ids == the solo completion ids');
    expect(
      streamedText.toString().trim(),
      soloText,
      reason: 'ST-G1: joined deltas == the solo wire text\n'
          'solo: $soloText\nstream: $streamedText',
    );
  });

  test('stream gate: stream:true serves OpenAI-style SSE at the wire', () async {
    final NativeQwenTextEngine engine;
    try {
      engine = await NativeQwenTextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native qwen unavailable: $error');
    }
    addTearDown(engine.dispose);
    if (!engine.supportsStreaming) {
      return markTestSkipped('native dylib lacks the streaming ABI');
    }
    final server = LayaQwenChatServer(
      engine: engine,
      // Explicit OFF here: this gate tests streaming, not coalescing; a
      // streamed request never enters the coalescer either way.
      coalesceWindow: Duration.zero,
    );
    await server.start();
    addTearDown(server.stop);

    const prompt =
        'Classify the text. Answer with exactly one of: allow, deny\n\n'
        'Text: The request asks to rename a folder.\nAnswer:';

    Future<http.Response> chat(Uri base, {required bool stream}) => http.post(
      base.replace(path: '/v1/chat/completions'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(<String, Object?>{
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': prompt},
        ],
        'max_tokens': 32,
        'stream': stream,
      }),
    );

    final plain = await chat(server.url, stream: false);
    expect(plain.statusCode, 200);
    final plainBody = jsonDecode(plain.body) as Map<String, dynamic>;
    final plainText =
        plainBody['choices'][0]['message']['content'] as String;

    final streamed = await chat(server.url, stream: true);
    expect(streamed.statusCode, 200);
    expect(
      streamed.headers['content-type'],
      contains('text/event-stream'),
      reason: 'ST-G2: the stream wire is SSE',
    );

    final frames = streamed.body
        .split('\n\n')
        .where((frame) => frame.startsWith('data: '))
        .map((frame) => frame.substring('data: '.length))
        .toList();
    expect(frames.last, '[DONE]', reason: 'ST-G2: the wire ends with [DONE]');
    final payloads = <Map<String, dynamic>>[
      for (final raw in frames.take(frames.length - 1))
        jsonDecode(raw) as Map<String, dynamic>,
    ];
    expect(payloads, isNotEmpty);
    for (final payload in payloads) {
      expect(payload['object'], 'chat.completion.chunk');
    }
    final content = StringBuffer();
    for (final payload in payloads) {
      final delta = payload['choices'][0]['delta'] as Map<String, dynamic>;
      content.write(delta['content'] ?? '');
    }
    final last = payloads.last;
    expect(last['choices'][0]['finish_reason'], 'stop',
        reason: 'ST-G2: the final frame carries finish_reason stop');
    expect((last['usage'] as Map<String, dynamic>)['completion_tokens'],
        greaterThan(0));

    expect(
      content.toString().trim(),
      plainText.trim(),
      reason: 'ST-G2: joined streamed content == the completion answer\n'
          'plain: $plainText\nstreamed: $content',
    );
  });
}
