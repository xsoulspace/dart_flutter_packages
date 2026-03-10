import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

enum WebSpeechRecognitionFailureKind {
  permissionOrServiceBlocked,
  invalidCaptureOrInput,
  runtimeEngineOrNetworkOrLanguage,
  unsupported,
}

class WebSpeechRecognitionAdapterException implements Exception {
  const WebSpeechRecognitionAdapterException({
    required this.kind,
    required this.reason,
    required this.message,
    this.details,
  });

  final WebSpeechRecognitionFailureKind kind;
  final String reason;
  final String message;
  final Object? details;

  Map<String, dynamic> toDetails() => <String, dynamic>{
    'reason': reason,
    if (details != null) 'details': details,
  };

  @override
  String toString() =>
      'WebSpeechRecognitionAdapterException(kind: $kind, reason: $reason, '
      'message: $message, details: $details)';
}

abstract interface class WebSpeechRecognitionAdapter {
  bool get hasSpeechRecognitionApi;

  bool get isChromiumFamily;

  Future<String> recognize({
    required InferenceAudioInput audioInput,
    String? language,
  });
}
