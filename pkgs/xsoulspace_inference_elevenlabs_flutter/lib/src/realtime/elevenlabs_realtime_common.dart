import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../elevenlabs_common.dart';
import '../elevenlabs_config.dart';

typedef ElevenLabsWebSocketConnector =
    WebSocketChannel Function(Uri uri, {Map<String, dynamic>? headers});

WebSocketChannel defaultElevenLabsWebSocketConnector(
  final Uri uri, {
  final Map<String, dynamic>? headers,
}) => IOWebSocketChannel.connect(uri, headers: headers);

Future<InferenceResult<Map<String, dynamic>>> resolveRealtimeAuthHeaders(
  final ElevenLabsAuthConfig authConfig,
) async {
  final token = await authConfig.resolveBearerToken();
  if (token != null) {
    return InferenceResult<Map<String, dynamic>>.ok(<String, dynamic>{
      'authorization': 'Bearer $token',
    });
  }

  final apiKey = authConfig.normalizedApiKey;
  if (apiKey != null) {
    return InferenceResult<Map<String, dynamic>>.ok(<String, dynamic>{
      'xi-api-key': apiKey,
    });
  }

  return InferenceResult<Map<String, dynamic>>.fail(
    code: errorCodeAuthFailed,
    message: 'Realtime ElevenLabs session requires bearer token or API key',
  );
}
