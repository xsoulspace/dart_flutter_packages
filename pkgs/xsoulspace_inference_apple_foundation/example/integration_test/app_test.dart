import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plugin availability and optional infer', (tester) async {
    await AppleFoundationInferenceClient().refreshAvailability();
    final available = AppleFoundationInferenceClient().isAvailable;

    if (!available) {
      return;
    }

    final client = AppleFoundationInferenceClient();
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'answer': <String, dynamic>{'type': 'string'},
      },
    };
    final result = await client.infer(
      const InferenceRequest(
        prompt: 'Reply with one word: ok.',
        outputSchema: schema,
        workingDirectory: '/tmp',
      ),
    );

    expect(result.success || result.error != null, isTrue);
    if (result.success) {
      expect(result.data, isNotNull);
      expect(result.data!.output, isA<Map<String, dynamic>>());
    } else {
      expect(result.error!.code, isNotEmpty);
    }
  });
}
