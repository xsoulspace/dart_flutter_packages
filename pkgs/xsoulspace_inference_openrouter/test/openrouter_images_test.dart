// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

OpenRouterInferenceClient _clientWithMock(
  http_testing.MockClientHandler handler, {
  String apiKey = 'test-key',
  String baseUrl = 'https://openrouter.ai/api/v1',
  ImageEndpointStyle? imageEndpointStyle,
  void Function(Map<String, Object?> event)? onTransportDiagnostic,
}) {
  final mock = http_testing.MockClient(handler);
  return OpenRouterInferenceClient(
    apiKey: apiKey,
    baseUrl: baseUrl,
    httpClient: mock,
    imageEndpointStyle: imageEndpointStyle,
    onTransportDiagnostic: onTransportDiagnostic,
  );
}

http_testing.MockClientHandler _respondWith(
  String body, {
  int statusCode = 200,
  void Function(http.Request request)? onRequest,
}) =>
    (request) async {
      onRequest?.call(request);
      return http.Response.bytes(
        utf8.encode(body),
        statusCode,
        headers: {'content-type': 'application/json'},
      );
    };

void main() {
  group('imagesUri derivation', () {
    test('openrouter style appends /images to the default root', () {
      final uri = imagesUri(
        'https://openrouter.ai/api/v1',
        ImageEndpointStyle.openRouterImages,
      );
      expect(uri.toString(), 'https://openrouter.ai/api/v1/images');
    });

    test('openai style appends /images/generations', () {
      final uri = imagesUri(
        'https://api-inference.modelscope.cn/v1',
        ImageEndpointStyle.openAiGenerations,
      );
      expect(
        uri.toString(),
        'https://api-inference.modelscope.cn/v1/images/generations',
      );
    });

    test('a root already naming the operation rides verbatim', () {
      expect(
        imagesUri(
          'https://gateway.internal/v1/images/generations',
          ImageEndpointStyle.openAiGenerations,
        ).toString(),
        'https://gateway.internal/v1/images/generations',
      );
      expect(
        imagesUri(
          'https://gateway.internal/v1/images',
          ImageEndpointStyle.openRouterImages,
        ).toString(),
        'https://gateway.internal/v1/images',
      );
    });

    test('an empty base url defaults to the OpenRouter root', () {
      expect(
        imagesUri('', ImageEndpointStyle.openRouterImages).toString(),
        'https://openrouter.ai/api/v1/images',
      );
    });
  });

  group('image task gating', () {
    test('image tasks refuse before any HTTP when no style is declared', () async {
      var called = false;
      final client = _clientWithMock((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final result = await client.infer(
        InferenceRequest.textToImage(prompt: 'a lighthouse'),
      );
      expect(result.success, isFalse);
      expect(result.error?.code, 'task_unsupported');
      expect(called, isFalse);
    });

    test('supportedTasks carries the image tasks only with a declared style', () {
      final chatOnly = OpenRouterInferenceClient(apiKey: 'k');
      final images = OpenRouterInferenceClient(
        apiKey: 'k',
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      expect(chatOnly.supportedTasks.contains(InferenceTask.textToImage), isFalse);
      expect(images.supportedTasks, containsAll(<InferenceTask>[
        InferenceTask.textToImage,
        InferenceTask.imageToImage,
      ]));
    });

    test('a non-empty cache intent on an image request refuses by name', () async {
      final client = _clientWithMock(
        _respondWith('{}'),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(
          prompt: 'a lighthouse',
          metadata: <String, dynamic>{
            'context_cache_intent': <String, Object?>{
              'writeAfterSegmentIds': <String>['messages[0]'],
              'lookupAfterSegmentIds': <String>[],
            },
          },
        ),
      );
      expect(result.success, isFalse);
      expect(result.error?.code, 'cache_intent_unsupported_for_task');
    });
  });

  group('image wire bodies', () {
    test('T2I body (openrouter style): typed options map, no chat keys', () async {
      Map<String, dynamic>? wire;
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"b64_json":"aGVsbG8=","media_type":"image/png"}]}',
          onRequest: (request) =>
              wire = jsonDecode(request.body) as Map<String, dynamic>,
        ),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(
          prompt: 'a lighthouse at dawn',
          imageOptions: const InferenceImageOptions(n: 2, aspectRatio: '16:9'),
          metadata: <String, dynamic>{'model': 'google/nano-banana-2'},
        ),
      );

      expect(result.success, isTrue);
      final sent = wire;
      expect(sent, isNotNull);
      // The wire golden: exactly the images-lane keys, no chat-lane keys.
      expect(sent!['model'], 'google/nano-banana-2');
      expect(sent['prompt'], 'a lighthouse at dawn');
      expect(sent['n'], 2);
      expect(sent['aspect_ratio'], '16:9');
      expect(sent.containsKey('messages'), isFalse);
      expect(sent.containsKey('max_tokens'), isFalse);
      expect(sent.containsKey('response_format'), isFalse);
      expect(sent.containsKey('input_references'), isFalse);
    });

    test('I2I body (openrouter style): input_references carries a data URL',
        () async {
      Map<String, dynamic>? wire;
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"b64_json":"aGVsbG8="}]}',
          onRequest: (request) =>
              wire = jsonDecode(request.body) as Map<String, dynamic>,
        ),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.imageToImage(
          prompt: 'make the sky stormy',
          imageInput: const InferenceImageInput.bytes(
            bytes: <int>[1, 2, 3],
            mimeType: 'image/png',
          ),
          imageOptions: const InferenceImageOptions(strength: 0.3),
        ),
      );

      expect(result.success, isTrue);
      final references = wire!['input_references'] as List;
      expect(references, hasLength(1));
      final reference = references.first as Map<String, dynamic>;
      expect(reference['type'], 'image_url');
      expect(
        (reference['image_url'] as Map)['url'],
        'data:image/png;base64,${base64Encode(<int>[1, 2, 3])}',
      );
      expect(wire!['strength'], 0.3);
    });

    test('I2I body (openai style): the reference image rides `image`',
        () async {
      Uri? uri;
      Map<String, dynamic>? wire;
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"url":"https://cdn.example.com/out.png"}]}',
          onRequest: (request) {
            uri = request.url;
            wire = jsonDecode(request.body) as Map<String, dynamic>;
          },
        ),
        baseUrl: 'https://api-inference.modelscope.cn/v1',
        imageEndpointStyle: ImageEndpointStyle.openAiGenerations,
      );
      final result = await client.infer(
        InferenceRequest.imageToImage(
          prompt: 'edit this',
          imageInput: const InferenceImageInput.bytes(
            bytes: <int>[4, 5],
            mimeType: 'image/jpeg',
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(
        uri.toString(),
        'https://api-inference.modelscope.cn/v1/images/generations',
      );
      expect(
        wire!['image'],
        'data:image/jpeg;base64,${base64Encode(<int>[4, 5])}',
      );
      expect(wire!.containsKey('input_references'), isFalse);
    });

    test('providerExtras pass verbatim and override typed fields', () async {
      Map<String, dynamic>? wire;
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"b64_json":"aGVsbG8="}]}',
          onRequest: (request) =>
              wire = jsonDecode(request.body) as Map<String, dynamic>,
        ),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(
          prompt: 'a lighthouse',
          imageOptions: const InferenceImageOptions(
            size: '1K',
            providerExtras: <String, dynamic>{
              'size': '2048x2048',
              'engine': 'qwen-image',
            },
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(wire!['size'], '2048x2048');
      expect(wire!['engine'], 'qwen-image');
    });

    test('a filePath input is read and encoded; an unreadable file refuses',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'inference_image_input_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/reference.png')
        ..writeAsBytesSync(<int>[7, 8, 9]);

      Map<String, dynamic>? wire;
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"b64_json":"aGVsbG8="}]}',
          onRequest: (request) =>
              wire = jsonDecode(request.body) as Map<String, dynamic>,
        ),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.imageToImage(
          prompt: 'edit this',
          imageInput: InferenceImageInput.filePath(
            filePath: file.path,
            mimeType: 'image/png',
          ),
        ),
      );
      expect(result.success, isTrue);
      expect(
        wire!['input_references'],
        isNotNull,
      );

      final missing = await client.infer(
        InferenceRequest.imageToImage(
          prompt: 'edit this',
          imageInput: InferenceImageInput.filePath(
            filePath: '${directory.path}/absent.png',
            mimeType: 'image/png',
          ),
        ),
      );
      expect(missing.success, isFalse);
      expect(missing.error?.code, 'image_input_unreadable');
    });
  });

  group('image response parsing', () {
    test('b64 responses produce bytes artifacts without warnings', () async {
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"b64_json":"aGVsbG8=","media_type":"image/png"},'
          '{"b64_json":"dw=="}],"usage":{"cost":0.05}}',
        ),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(prompt: 'a lighthouse', metadata: {
          'model': 'google/nano-banana-2',
        }),
      );

      expect(result.success, isTrue);
      final response = result.data!;
      expect(response.task, InferenceTask.textToImage);
      expect(response.imageArtifacts, hasLength(2));
      expect(response.imageArtifacts[0].bytesBase64, 'aGVsbG8=');
      expect(response.imageArtifacts[0].mimeType, 'image/png');
      expect(response.imageArtifacts[1].mimeType, 'image/png');
      expect(response.warnings, isEmpty);
      expect(response.imageArtifacts.every((a) => a.carrierCount == 1), isTrue);
      expect(response.meta['usage_reported'], isTrue);
    });

    test('url responses carry the expiring warning and extension mime type',
        () async {
      final client = _clientWithMock(
        _respondWith(
          '{"data":[{"url":"https://cdn.example.com/out/abc.webp"}]}',
        ),
        baseUrl: 'https://api-inference.modelscope.cn/v1',
        imageEndpointStyle: ImageEndpointStyle.openAiGenerations,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(prompt: 'a lighthouse'),
      );

      expect(result.success, isTrue);
      final response = result.data!;
      expect(response.imageArtifacts, hasLength(1));
      expect(
        response.imageArtifacts.single.url,
        'https://cdn.example.com/out/abc.webp',
      );
      expect(response.imageArtifacts.single.mimeType, 'image/webp');
      expect(response.warnings, contains('image_url_expiring'));
    });

    test('an empty data array refuses as output_empty', () async {
      final client = _clientWithMock(
        _respondWith('{"data":[]}'),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(prompt: 'a lighthouse'),
      );
      expect(result.success, isFalse);
      expect(result.error?.code, 'output_empty');
    });

    test('HTTP errors keep the chat lane\'s mapping and outcome event',
        () async {
      final events = <Map<String, Object?>>[];
      final client = _clientWithMock(
        _respondWith('{"error":{"message":"content policy"}}', statusCode: 400),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
        onTransportDiagnostic: events.add,
      );
      final result = await client.infer(
        InferenceRequest.textToImage(prompt: 'a lighthouse'),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'http_error');
      expect(result.error?.message, 'content policy');
      expect(events.last['type'], 'openrouter.result');
      expect(events.last['lane'], 'images');
      expect(events.last['ok'], isFalse);
    });
  });

  group('image diagnostics size law', () {
    test('transport events carry size markers, never image bytes', () async {
      final events = <Map<String, Object?>>[];
      final payload = List<int>.generate(2048, (i) => i % 256);
      final client = _clientWithMock(
        _respondWith('{"data":[{"b64_json":"${base64Encode(payload)}"}]}'),
        imageEndpointStyle: ImageEndpointStyle.openRouterImages,
        onTransportDiagnostic: events.add,
      );
      final result = await client.infer(
        InferenceRequest.imageToImage(
          prompt: 'edit this',
          imageInput: InferenceImageInput.bytes(
            bytes: payload,
            mimeType: 'image/png',
          ),
        ),
      );

      expect(result.success, isTrue);
      final encodedEvents = jsonEncode(events);
      expect(encodedEvents.contains('data:image/'), isFalse);
      expect(encodedEvents.contains(base64Encode(payload)), isFalse);
      final post = events.firstWhere((e) => e['type'] == 'openrouter.post');
      expect((post['body'] as String), contains('[[data-url:'));
    });
  });
}
