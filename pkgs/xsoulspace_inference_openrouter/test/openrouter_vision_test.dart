// ignore_for_file: lines_longer_than_80_chars

/// Native-image-assets wave C — the VISION lane on the OpenRouter
/// transport: an `imageToText` request renders the user content as the
/// typed part array (text + image_url data URL), the text paths stay
/// byte-identical, and the diagnostics size law covers the chat lane
/// (data URLs become size markers in every diagnostic copy, never in
/// the wire body).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

const String _chatBody =
    '{"id":"chatcmpl-1","choices":[{"message":{"role":"assistant",'
    '"content":"a lighthouse at dawn"}}],"usage":{"prompt_tokens":10}}';

OpenRouterInferenceClient _clientWithMock(
  http_testing.MockClientHandler handler, {
  String apiKey = 'test-key',
  String baseUrl = 'https://openrouter.ai/api/v1',
  void Function(Map<String, Object?> event)? onTransportDiagnostic,
}) => OpenRouterInferenceClient(
  apiKey: apiKey,
  baseUrl: baseUrl,
  httpClient: http_testing.MockClient(handler),
  onTransportDiagnostic: onTransportDiagnostic,
);

http_testing.MockClientHandler _respondWith(
  String body, {
  void Function(http.Request request)? onRequest,
}) =>
    (request) async {
      onRequest?.call(request);
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    };

void main() {
  test('imageToText renders the typed content array on the wire', () async {
    http.Request? captured;
    final client = _clientWithMock(_respondWith(_chatBody, onRequest: (r) => captured = r));
    final result = await client.infer(
      InferenceRequest.imageToText(
        prompt: 'What does this sign say?',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[1, 2, 3],
          mimeType: 'image/png',
        ),
      ),
    );
    expect(result.success, isTrue, reason: result.error?.toString());
    final body = jsonDecode(utf8.decode(captured!.bodyBytes)) as Map;
    final messages = body['messages'] as List;
    expect(messages, hasLength(1)); // no system prompt → one user turn
    final content = (messages.first as Map)['content'] as List;
    expect((content.first as Map)['type'], 'text');
    expect((content.first as Map)['text'], 'What does this sign say?');
    final imagePart = content.last as Map;
    expect(imagePart['type'], 'image_url');
    expect(
      (imagePart['image_url'] as Map)['url'],
      'data:image/png;base64,${base64Encode(<int>[1, 2, 3])}',
    );
  });

  test('a system prompt rides alongside the vision user turn', () async {
    http.Request? captured;
    final client = _clientWithMock(_respondWith(_chatBody, onRequest: (r) => captured = r));
    await client.infer(
      InferenceRequest.imageToText(
        prompt: 'describe',
        systemPrompt: 'You caption images.',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[9],
          mimeType: 'image/jpeg',
        ),
      ),
    );
    final messages =
        (jsonDecode(utf8.decode(captured!.bodyBytes)) as Map)['messages']
            as List;
    expect(messages, hasLength(2));
    expect((messages.first as Map)['role'], 'system');
    expect((messages.last as Map)['role'], 'user');
  });

  test('the wire body carries the pixels; diagnostics carry SIZE MARKERS',
      () async {
    final dataUrl = 'data:image/png;base64,${base64Encode(<int>[1, 2, 3])}';
    final diagnostics = <Map<String, Object?>>[];
    final client = _clientWithMock(
      _respondWith(_chatBody),
      onTransportDiagnostic: diagnostics.add,
    );
    await client.infer(
      InferenceRequest.imageToText(
        prompt: 'describe',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[1, 2, 3],
          mimeType: 'image/png',
        ),
      ),
    );
    // The transport diagnostic post event must NOT carry the data URL.
    final post = diagnostics
        .whereType<Map<String, Object?>>()
        .firstWhere((event) => event['type'] == 'openrouter.post');
    final diagnosticBody = post['body']! as String;
    expect(diagnosticBody.contains(dataUrl), isFalse,
        reason: 'pixels leaked into transport diagnostics');
    expect(diagnosticBody, contains('[[data-url:'));
    expect(diagnosticBody, contains('chars]]'));
  });

  test('text-only bodies keep byte-identical diagnostics (no markers)',
      () async {
    final diagnostics = <Map<String, Object?>>[];
    final client = _clientWithMock(
      _respondWith(_chatBody),
      onTransportDiagnostic: diagnostics.add,
    );
    await client.infer(
      InferenceRequest(prompt: 'plain text round', task: InferenceTask.text),
    );
    final post = diagnostics
        .whereType<Map<String, Object?>>()
        .firstWhere((event) => event['type'] == 'openrouter.post');
    expect((post['body']! as String).contains('[[data-url:'), isFalse);
  });

  test('imageToText is supported WITHOUT a declared images endpoint',
      () async {
    final client = _clientWithMock(_respondWith(_chatBody));
    final result = await client.infer(
      InferenceRequest.imageToText(
        prompt: 'describe',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[1],
          mimeType: 'image/png',
        ),
      ),
    );
    expect(result.success, isTrue,
        reason: 'vision rides the chat endpoint — no images gate');
  });

  test('a byte-FILE image input reads from disk for the data URL',
      () async {
    final temp = Directory.systemTemp.createTempSync('vision-file-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/ref.png')
      ..writeAsBytesSync(<int>[7, 7, 7]);
    http.Request? captured;
    final client = _clientWithMock(_respondWith(_chatBody, onRequest: (r) => captured = r));
    final result = await client.infer(
      InferenceRequest.imageToText(
        prompt: 'describe',
        imageInput: InferenceImageInput.filePath(
          filePath: file.path,
          mimeType: 'image/png',
        ),
      ),
    );
    expect(result.success, isTrue);
    final body = jsonDecode(utf8.decode(captured!.bodyBytes)) as Map;
    final content =
        ((body['messages'] as List).last as Map)['content'] as List;
    expect(
      ((content.last as Map)['image_url'] as Map)['url'],
      'data:image/png;base64,${base64Encode(<int>[7, 7, 7])}',
    );
  });
}
