class InferenceRequest {
  const InferenceRequest({
    required this.prompt,
    required this.outputSchema,
    required this.workingDirectory,
    this.metadata = const <String, dynamic>{},
  });

  final String prompt;
  final Map<String, dynamic> outputSchema;
  final String workingDirectory;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'output_schema': outputSchema,
        'working_directory': workingDirectory,
        'metadata': metadata,
      };
}

class InferenceResponse {
  const InferenceResponse({
    required this.output,
    this.rawOutput,
    this.warnings = const <String>[],
    this.meta = const <String, dynamic>{},
  });

  final Map<String, dynamic> output;
  final String? rawOutput;
  final List<String> warnings;
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson() => {
        'output': output,
        if (rawOutput != null) 'raw_output': rawOutput,
        'warnings': warnings,
        'meta': meta,
      };
}
