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
        'Respond with a single JSON object that conforms to this schema '
        '(no other text):',
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
    writeln();
    write(schemaJson);
  }
}
