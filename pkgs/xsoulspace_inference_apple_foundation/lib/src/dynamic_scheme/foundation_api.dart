import 'package:flutter/services.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Opaque handle returned to Dart after successful materialization.
extension type const GenerationSchemaHandle(String value) {}

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

  void init() {
    _addToolCallHanlders();
  }

  void _addToolCallHanlders() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToolCall') {
        final name = call.arguments['name'] as String;
        final arguments = call.arguments['arguments'];

        final handler = _toolHandlers[name];
        if (handler == null) {
          throw PlatformException(
            code: 'unknown_tool',
            message: 'No handler registered for $name',
          );
        }

        // Execute the real Dart logic and return the result
        final result = await handler(arguments);
        return result; // this value goes back to Swift ToolInvoker
      }
      throw PlatformException(code: 'not_implemented');
    });
  }

  // Registry of Dart tool implementations
  static final Map<String, ToolCallCallback> _toolHandlers = {};
  void addToolCall(String toolCallName, ToolCallCallback function) {
    _toolHandlers[toolCallName] = function;
  }

  void removeToolCall(String toolCallName) {
    _toolHandlers.remove(toolCallName);
  }

  void addTools(ToolRegistry toolRegistry) {
    for (var MapEntry(:key, value: callback) in toolRegistry.tools.entries) {
      addToolCall(key, callback.execute);
    }
  }

  void removeTools(ToolRegistry toolRegistry) {
    toolRegistry.tools.keys.map(removeToolCall);
  }

  void dispose() {
    _toolHandlers.clear();
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
