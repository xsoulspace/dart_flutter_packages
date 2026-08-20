import 'package:flutter/services.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Opaque handle returned to Dart after successful materialization.
extension type const GenerationSchemaHandle(String value) {}

/// A per-request, isolated tool-handler registry.
///
/// Each `generate` call owns its own handlers keyed by a `requestId`. Swift
/// threads the `requestId` back on every `onToolCall`, so concurrent requests
/// can use the same tool name with different handlers without colliding —
/// true per-request isolation, no ref-counting needed.
class FoundationApi {
  FoundationApi({required this._channel});

  final MethodChannel _channel;

  /// Serializes the bundle and asks the native side to materialize
  /// a real GenerationSchema.
  ///
  /// Returns an opaque handle / id that can later be used with the
  /// LanguageModelSession on the Swift side, or throws on failure.
  Future<GenerationSchemaHandle> materialize(SchemaBundle bundle) async {
    final json = bundle.toJson();

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'materializeSchema',
      json,
    );

    return GenerationSchemaHandle(jsonDecodeString(result?['id']));
  }

  void init({ToolCallCallback? toolCallback}) {
    _addToolCallHanlders();
  }

  void _addToolCallHanlders() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToolCall') {
        final requestId = call.arguments['requestId'] as String? ?? '';
        final name = call.arguments['name'] as String;
        final arguments = call.arguments['arguments'];

        final handler = _resolveHandler(requestId, name);
        if (handler == null) {
          throw PlatformException(
            code: 'unknown_tool',
            message: 'No handler registered for $name (request $requestId)',
          );
        }

        // Execute the real Dart logic and return the result
        final result = await handler(arguments);
        return result; // this value goes back to Swift ToolInvoker
      }
      throw PlatformException(code: 'not_implemented');
    });
  }

  // Request-scoped tool handlers: requestId → (tool name → callback).
  final Map<String, Map<String, ToolCallCallback>> _requestHandlers = {};

  /// Install [registry]'s handlers for [requestId]. Call before `generate`.
  void beginRequest(String requestId, ToolRegistry registry) {
    final scoped = _requestHandlers.putIfAbsent(requestId, () => {});
    for (final entry in registry.tools.entries) {
      scoped[entry.key.value] = entry.value.execute;
    }
  }

  /// Remove [requestId]'s handlers. Call in `finally` after `generate`.
  void endRequest(String requestId) {
    _requestHandlers.remove(requestId);
  }

  ToolCallCallback? _resolveHandler(String requestId, String name) {
    final scoped = _requestHandlers[requestId];
    if (scoped == null) return null;
    return scoped[name];
  }

  void dispose() {
    _requestHandlers.clear();
  }

  Future<bool> isAvailable() async {
    final result = await _channel.invokeMethod<bool>('isAvailable');
    return jsonDecodeBool(result);
  }

  Future<String> generate({required Map<String, dynamic> json}) async {
    final response = await _channel.invokeMethod<String>('generate', json);
    return jsonDecodeString(response);
  }
}
