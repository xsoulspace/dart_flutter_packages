class InferenceError {
  const InferenceError({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };
}

class InferenceResult<T> {
  const InferenceResult({
    required this.success,
    this.data,
    this.error,
    this.warnings = const <String>[],
    this.meta = const <String, dynamic>{},
  });

  factory InferenceResult.ok(
    T data, {
    List<String> warnings = const <String>[],
    Map<String, dynamic> meta = const <String, dynamic>{},
  }) => InferenceResult<T>(
    success: true,
    data: data,
    warnings: warnings,
    meta: meta,
  );

  factory InferenceResult.fail({
    required String code,
    required String message,
    Object? details,
    List<String> warnings = const <String>[],
    Map<String, dynamic> meta = const <String, dynamic>{},
  }) => InferenceResult<T>(
    success: false,
    error: InferenceError(code: code, message: message, details: details),
    warnings: warnings,
    meta: meta,
  );

  final bool success;
  final T? data;
  final InferenceError? error;
  final List<String> warnings;
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson(Object? Function(T value) toData) =>
      <String, dynamic>{
        'success': success,
        'data': data == null ? null : toData(data as T),
        if (error != null) 'error': error!.toJson(),
        'warnings': warnings,
        'meta': meta,
      };
}
