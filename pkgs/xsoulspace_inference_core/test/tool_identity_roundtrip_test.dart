import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test(
    'repeated calls retain independent identity after serialization',
    () {
      const response = InferenceResponse(
        toolCalls: [
          ToolCall(
            name: ToolName('inspect'),
            arguments: {'path': 'a'},
            callId: 'one',
            namespace: 'harness',
          ),
          ToolCall(
            name: ToolName('inspect'),
            arguments: {'path': 'b'},
            callId: 'two',
            namespace: 'harness',
          ),
        ],
        toolResults: [
          ToolExecutionResult(name: 'inspect', output: null, callId: 'one'),
          ToolExecutionResult(
            name: 'inspect',
            output: 'observed',
            callId: 'two',
          ),
        ],
      );
      final restored = InferenceResponse.fromJson(response.toJson());
      expect(restored.toolCalls.map((c) => c.callId), ['one', 'two']);
      expect(restored.toolCalls.map((c) => c.namespace), [
        'harness',
        'harness',
      ]);
      expect(restored.toolResults.map((r) => r.callId), ['one', 'two']);
      expect(restored.toolResults.first.output, isNull);
    },
  );
  test(
    'legacy tool constructors and serialized results retain optional identity',
    () {
      final call = ToolCall.fromJson({
        'name': 'inspect',
        'arguments': {'path': 'a'},
      });
      final output = ToolExecutionResult.fromJson({
        'name': 'inspect',
        'output': 'old',
      });
      expect(call.callId, isNull);
      expect(call.namespace, isNull);
      expect(output.callId, isNull);
      expect(output.toJson(), {'name': 'inspect', 'output': 'old'});
    },
  );
}
