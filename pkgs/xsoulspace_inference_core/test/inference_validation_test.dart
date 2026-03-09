import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('parseStrictJsonObject parses valid JSON objects', () {
    final result = parseStrictJsonObject('{"ok":true,"n":1}');

    expect(result.success, isTrue);
    expect(result.data, isNotNull);
    expect(result.data!['ok'], isTrue);
  });

  test('parseStrictJsonObject rejects non-object JSON', () {
    final result = parseStrictJsonObject('[1,2,3]');

    expect(result.success, isFalse);
    expect(result.error?.code, 'json_not_object');
  });

  test('validateRequiredKeys reports missing fields', () {
    final result = validateRequiredKeys(
      object: const <String, dynamic>{'a': 1},
      requiredKeys: const <String>['a', 'b'],
    );

    expect(result.success, isFalse);
    expect(result.error?.code, 'required_keys_missing');
    final details = result.error?.details as Map<String, dynamic>?;
    expect(details?['missing_keys'], contains('b'));
  });

  test('validateInferenceRequest rejects empty prompt', () {
    final result = validateInferenceRequest(
      const InferenceRequest(
        prompt: '   ',
        outputSchema: <String, dynamic>{'type': 'object'},
        workingDirectory: '/tmp',
      ),
    );

    expect(result.success, isFalse);
    expect(result.error?.code, 'request_prompt_empty');
  });

  test('validateSchemaDefinition rejects malformed required field', () {
    final result = validateSchemaDefinition(const <String, dynamic>{
      'type': 'object',
      'required': <Object?>['ok', 1],
    });

    expect(result.success, isFalse);
    expect(result.error?.code, 'schema_invalid_required_field');
  });

  test('validateJsonAgainstSchema validates nested objects and arrays', () {
    final schema = <String, dynamic>{
      'type': 'object',
      'required': <String>['items'],
      'properties': <String, dynamic>{
        'items': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{
            'type': 'object',
            'required': <String>['id', 'score'],
            'properties': <String, dynamic>{
              'id': <String, dynamic>{'type': 'string'},
              'score': <String, dynamic>{'type': 'number'},
            },
          },
        },
      },
    };

    final result = validateJsonAgainstSchema(
      value: const <String, dynamic>{
        'items': <Map<String, Object?>>[
          <String, Object?>{'id': 'a1', 'score': 1},
        ],
      },
      schema: schema,
    );

    expect(result.success, isTrue);
  });

  test('validateJsonAgainstSchema reports nested type mismatch', () {
    final schema = <String, dynamic>{
      'type': 'object',
      'required': <String>['items'],
      'properties': <String, dynamic>{
        'items': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{
            'type': 'object',
            'required': <String>['id'],
            'properties': <String, dynamic>{
              'id': <String, dynamic>{'type': 'string'},
            },
          },
        },
      },
    };

    final result = validateJsonAgainstSchema(
      value: const <String, dynamic>{
        'items': <Map<String, Object?>>[
          <String, Object?>{'id': 1},
        ],
      },
      schema: schema,
    );

    expect(result.success, isFalse);
    expect(result.error?.code, 'schema_type_mismatch');
    final details = result.error?.details as Map<String, dynamic>?;
    expect(details?['path'], r'$.items[0].id');
  });

  test('validateInferenceRequest rejects STT request without audio input', () {
    final result = validateInferenceRequest(
      const InferenceRequest(
        prompt: '',
        outputSchema: <String, dynamic>{},
        workingDirectory: '/tmp',
        task: InferenceTask.speechToText,
      ),
    );

    expect(result.success, isFalse);
    expect(result.error?.code, errorCodeAudioInputMissing);
  });

  test('validateInferenceRequest rejects empty TTS text', () {
    final result = validateInferenceRequest(
      InferenceRequest.textToSpeech(text: '   ', workingDirectory: '/tmp'),
    );

    expect(result.success, isFalse);
    expect(result.error?.code, errorCodeTtsTextEmpty);
  });

  test('validateInferenceRequest accepts STT file-path request', () {
    final result = validateInferenceRequest(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.filePath(
          filePath: '/tmp/audio.wav',
          mimeType: 'audio/wav',
        ),
        workingDirectory: '/tmp',
      ),
    );

    expect(result.success, isTrue);
  });

  test('normalizeTranscript strips punctuation and collapses whitespace', () {
    final normalized = normalizeTranscript(
      'Hi,   world!!!  this... is\tan\nexample.',
    );

    expect(normalized, 'Hi world this is an example');
  });
}
