import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  group('ChatMessage multipart (native-image-assets wave C)', () {
    test('a plain message keeps the String content shape (byte-identical)',
        () {
      final json = ChatMessage.user('hello').toJson();
      expect(json, <String, dynamic>{'role': 'user', 'content': 'hello'});
    });

    test('userParts joins the text parts into the string projection', () {
      final message = ChatMessage.userParts([
        ChatMessagePart.text('What is in this image?'),
        ChatMessagePart.imageDataUrl('data:image/png;base64,QUJD'),
      ]);
      expect(message.role, ChatRole.user);
      expect(message.content, 'What is in this image?');
      expect(message.parts, hasLength(2));
      expect(message.parts![0].isImage, isFalse);
      expect(message.parts![1].isImage, isTrue);
    });

    test('multipart JSON renders the content ARRAY on the wire', () {
      final json = ChatMessage.userParts([
        ChatMessagePart.text('What is in this image?'),
        ChatMessagePart.imageDataUrl('data:image/png;base64,QUJD'),
      ]).toJson();
      final encoded = jsonEncode(json);
      expect(encoded, contains('"content":[{"type":"text"'));
      expect(encoded, contains('"type":"image_url"'));
      expect(encoded, contains('"url":"data:image/png;base64,QUJD"'));
    });

    test('multipart JSON round-trips through fromJson', () {
      final message = ChatMessage.fromJson(
        jsonDecode(
          jsonEncode(
            ChatMessage.userParts([
              ChatMessagePart.text('q'),
              ChatMessagePart.imageDataUrl('data:image/jpeg;base64,QUJD'),
            ]).toJson(),
          ),
        ) as Map<String, dynamic>,
      );
      expect(message.parts, hasLength(2));
      expect(message.content, 'q');
      expect(message.parts![1].imageDataUrl, 'data:image/jpeg;base64,QUJD');
    });

    test('InferenceTask.imageToText exists and names itself', () {
      expect(InferenceTask.imageToText.name, 'imageToText');
      expect(
        InferenceTask.fromJson('imageToText'),
        InferenceTask.imageToText,
      );
    });

    test('InferenceRequest.imageToText carries prompt + image input', () {
      final request = InferenceRequest.imageToText(
        prompt: 'What does this sign say?',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[1, 2, 3],
          mimeType: 'image/jpeg',
        ),
      );
      expect(request.task, InferenceTask.imageToText);
      expect(request.prompt, 'What does this sign say?');
      expect(request.imageInput!.resolvedSource, InferenceImageSource.bytes);
    });

    test('imageToText without an image input refuses by name', () {
      final request = InferenceRequest.imageToText(
        prompt: 'describe',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[],
          mimeType: 'image/png',
        ),
      );
      // The validation contract: an empty-bytes carrier is INVALID
      // (source_missing), and a MISSING carrier is image_input_missing.
      final invalid = validateInferenceRequest(request);
      expect(invalid.success, isFalse);
      expect(invalid.error?.code, 'image_input_invalid');

      final request2 = InferenceRequest(
        prompt: 'describe',
        task: InferenceTask.imageToText,
      );
      final missing = validateInferenceRequest(request2);
      expect(missing.success, isFalse);
      expect(missing.error?.code, 'image_input_missing');
    });

    test('imageToText with an empty prompt refuses by name', () {
      final request = InferenceRequest.imageToText(
        prompt: '   ',
        imageInput: const InferenceImageInput.bytes(
          bytes: <int>[1],
          mimeType: 'image/png',
        ),
      );
      final result = validateInferenceRequest(request);
      expect(result.success, isFalse);
      expect(result.error?.code, 'image_prompt_empty');
    });
  });
}
