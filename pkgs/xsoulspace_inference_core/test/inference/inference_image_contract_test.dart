import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('InferenceRequest textToImage serialization round-trips', () {
    final request = InferenceRequest.textToImage(
      prompt: 'a lighthouse at dawn',
      imageOptions: const InferenceImageOptions(
        n: 2,
        aspectRatio: '16:9',
        quality: 'high',
        outputFormat: 'png',
        negativePrompt: 'fog',
        providerExtras: <String, dynamic>{'engine': 'qwen-image'},
      ),
      metadata: const <String, dynamic>{'seed_hint': 'unit_test'},
    );

    final decoded = InferenceRequest.fromJson(request.value);

    expect(decoded.task, InferenceTask.textToImage);
    expect(decoded.prompt, 'a lighthouse at dawn');
    expect(decoded.imageInput, isNull);
    expect(decoded.imageOptions, isNotNull);
    expect(decoded.imageOptions!.n, 2);
    expect(decoded.imageOptions!.aspectRatio, '16:9');
    expect(decoded.imageOptions!.quality, 'high');
    expect(decoded.imageOptions!.outputFormat, 'png');
    expect(decoded.imageOptions!.negativePrompt, 'fog');
    expect(decoded.imageOptions!.providerExtras['engine'], 'qwen-image');
  });

  test('InferenceRequest imageToImage serialization round-trips', () {
    final request = InferenceRequest.imageToImage(
      prompt: 'make the sky stormy',
      imageInput: const InferenceImageInput.bytes(
        bytes: <int>[9, 8, 7],
        mimeType: 'image/png',
      ),
      imageOptions: const InferenceImageOptions(strength: 0.4, size: '1K'),
    );

    final decoded = InferenceRequest.fromJson(request.value);

    expect(decoded.task, InferenceTask.imageToImage);
    expect(decoded.prompt, 'make the sky stormy');
    expect(decoded.imageInput, isNotNull);
    expect(decoded.imageInput!.resolvedSource, InferenceImageSource.bytes);
    expect(decoded.imageInput!.bytes, <int>[9, 8, 7]);
    expect(decoded.imageInput!.mimeType, 'image/png');
    expect(decoded.imageOptions!.strength, 0.4);
    expect(decoded.imageOptions!.size, '1K');
  });

  test('InferenceImageInput infers source when discriminant is absent', () {
    final decoded = InferenceImageInput.fromJson(const <String, dynamic>{
      'file_path': '/tmp/reference.png',
      'mime_type': 'image/png',
    });

    expect(decoded.source, isNull);
    expect(decoded.resolvedSource, InferenceImageSource.filePath);
    expect(decoded.filePath, '/tmp/reference.png');
  });

  test('InferenceImageArtifact keeps exactly one carrier on the wire', () {
    const bytesArtifact = InferenceImageArtifact(
      mimeType: 'image/png',
      bytesBase64: 'aGVsbG8=',
    );
    const urlArtifact = InferenceImageArtifact(
      mimeType: 'image/png',
      url: 'https://example.com/image.png',
    );
    const fileArtifact = InferenceImageArtifact(
      mimeType: 'image/png',
      filePath: '/tmp/generated.png',
    );

    expect(bytesArtifact.carrierCount, 1);
    expect(urlArtifact.carrierCount, 1);
    expect(fileArtifact.carrierCount, 1);

    // Empty carriers are dropped, never emitted as nulls.
    expect(bytesArtifact.toJson().containsKey('url'), isFalse);
    expect(bytesArtifact.toJson().containsKey('file_path'), isFalse);
    expect(urlArtifact.toJson()['url'], 'https://example.com/image.png');

    for (final artifact in [bytesArtifact, urlArtifact, fileArtifact]) {
      final decoded = InferenceImageArtifact.fromJson(artifact.toJson());
      expect(decoded.carrierCount, 1);
      expect(decoded.mimeType, 'image/png');
    }
  });

  test('InferenceResponse image artifacts round-trip in order', () {
    const response = InferenceResponse(
      task: InferenceTask.textToImage,
      warnings: <String>['image_url_expiring'],
      imageArtifacts: <InferenceImageArtifact>[
        InferenceImageArtifact(
          mimeType: 'image/png',
          bytesBase64: 'aGVsbG8=',
        ),
        InferenceImageArtifact(
          mimeType: 'image/png',
          url: 'https://example.com/second.png',
        ),
      ],
    );

    final decoded = InferenceResponse.fromJson(response.toJson());

    expect(decoded.task, InferenceTask.textToImage);
    expect(decoded.imageArtifacts, hasLength(2));
    expect(decoded.imageArtifacts[0].bytesBase64, 'aGVsbG8=');
    expect(decoded.imageArtifacts[1].url, 'https://example.com/second.png');
    expect(decoded.warnings, contains('image_url_expiring'));
  });

  test('a chat request carries no image keys at all (absent, not null)', () {
    final request = InferenceRequest(prompt: 'hello');
    expect(request.value.containsKey('image_input'), isFalse);
    expect(request.value.containsKey('image_options'), isFalse);
    expect(request.imageInput, isNull);
    expect(request.imageOptions, isNull);
  });

  test('validation refuses an empty text-to-image prompt', () {
    final result = validateInferenceRequest(
      InferenceRequest.textToImage(prompt: '  '),
    );
    expect(result.success, isFalse);
    expect(result.error?.code, 'image_prompt_empty');
  });

  test('validation requires an imageInput for image-to-image', () {
    final result = validateInferenceRequest(
      InferenceRequest(
        prompt: 'edit this',
        task: InferenceTask.imageToImage,
      ),
    );
    expect(result.success, isFalse);
    expect(result.error?.code, 'image_input_missing');
  });

  test('validation refuses an ambiguous image input', () {
    final result = validateInferenceRequest(
      InferenceRequest.imageToImage(
        prompt: 'edit this',
        imageInput: const InferenceImageInput(
          mimeType: 'image/png',
          filePath: '/tmp/ref.png',
          bytes: <int>[1],
        ),
      ),
    );
    expect(result.success, isFalse);
    expect(result.error?.code, 'image_input_invalid');
    expect(
      (result.error?.details as Map?)?['reason'],
      'ambiguous_source',
    );
  });

  test('validation accepts well-formed image requests', () {
    final textToImage = validateInferenceRequest(
      InferenceRequest.textToImage(prompt: 'a lighthouse'),
    );
    expect(textToImage.success, isTrue);

    final imageToImage = validateInferenceRequest(
      InferenceRequest.imageToImage(
        prompt: 'edit this',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[1, 2, 3],
          mimeType: 'image/jpeg',
        ),
      ),
    );
    expect(imageToImage.success, isTrue);
  });
}
