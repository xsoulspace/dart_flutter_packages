import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';
import 'package:test/test.dart';

void main() {
  group('chatCompletionsUri', () {
    test('the default root yields the historical endpoint', () {
      expect(
        chatCompletionsUri('https://openrouter.ai/api/v1').toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
    });

    test('a declared root reaches its own host', () {
      expect(
        chatCompletionsUri('https://gateway.internal/v1').toString(),
        'https://gateway.internal/v1/chat/completions',
      );
    });

    test('a root that already names the operation is used verbatim', () {
      expect(
        chatCompletionsUri('https://gateway.internal/v1/chat/completions')
            .toString(),
        'https://gateway.internal/v1/chat/completions',
      );
    });

    test('a trailing slash does not double the separator', () {
      expect(
        chatCompletionsUri('https://gateway.internal/v1/').toString(),
        'https://gateway.internal/v1/chat/completions',
      );
    });

    test('a loopback root keeps its scheme, host and port', () {
      expect(
        chatCompletionsUri('http://127.0.0.1:8080/v1').toString(),
        'http://127.0.0.1:8080/v1/chat/completions',
      );
    });

    test('an empty root falls back to the historical endpoint', () {
      expect(
        chatCompletionsUri('   ').toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
    });
  });
}
