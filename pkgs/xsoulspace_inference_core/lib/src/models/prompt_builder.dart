// make prompt builder to SIMD-like | Column-oriented - wire to ecsly
import 'dart:convert';

// TODO(arenukvern): maybe think to implement builder pattern
// class Builder {
//   /// basically it is column, with hot swappable and cold swapable parts
//   PromptBuilder build() => PromptBuilder([
//     SystemPromptBuilder(),
//     ToolCallsPromptBuilder(), /// this could be compressed
//     UserPromptBuilder(),
//   ]);
// }
class PromptBuilder extends StringBuffer {
  PromptBuilder(
    String super.content, {
    this.structuredOutputSystemPrompt =
        'FINAL RESPONSE FORMAT'
        'When you have all the information you need (or when no tool is required),'
        'your entire reply must be a single valid JSON object that matches this schema.'
        'No markdown, no explanation, no text before or after the JSON.'
        ''
        'Schema:',
  });
  final String structuredOutputSystemPrompt;

  static final empty = PromptBuilder('');

  void skipLines({final int count = 2}) {
    for (var i = 0; i < count; i++) {
      writeln();
    }
  }

  void writeStructuredOutputPrompt(
    final Map<String, dynamic> outputSchema, {
    final String indent = '  ',
  }) {
    if (outputSchema.isEmpty || structuredOutputSystemPrompt.isEmpty) return;

    final schemaJson = JsonEncoder.withIndent(indent).convert(outputSchema);

    skipLines();
    write(structuredOutputSystemPrompt);
    // 'Example of a correct final response:'
    // '{"answer": "It will be cloudy at 5pm with a temperature of 18°C"}'

    writeln();
    write(schemaJson);
  }
}
