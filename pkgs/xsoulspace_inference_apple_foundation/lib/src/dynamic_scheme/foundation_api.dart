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

  void init({ToolCallCallback? toolCallback}) {
    _addToolCallHanlders();
  }

  void _addToolCallHanlders() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToolCall') {
        final name = call.arguments['name'] as String;
        final arguments = call.arguments['arguments'];

        final entry = _toolHandlers[name];
        if (entry == null) {
          throw PlatformException(
            code: 'unknown_tool',
            message: 'No handler registered for $name',
          );
        }

        // Execute the real Dart logic and return the result
        final result = await entry.callback(arguments);
        return result; // this value goes back to Swift ToolInvoker
      }
      throw PlatformException(code: 'not_implemented');
    });
  }

  // Registry of Dart tool implementations, reference-counted per tool name.
  //
  // Swift's `onToolCall` invokes Dart by tool name only. Multiple concurrent
  // `generate` calls may add/remove the same tool; a plain map would let one
  // request's `removeTools` wipe a handler another in-flight request still
  // needs (a cross-request race). Ref-counting each tool name so a handler is
  // only removed when the last owner releases it keeps the registry correct
  // without changing the Swift protocol.
  static final Map<ToolName, _ToolHandlerEntry> _toolHandlers = {};

  void addToolCall(ToolName toolCallName, ToolCallCallback function) {
    final existing = _toolHandlers[toolCallName];
    if (existing != null) {
      existing.refCount++;
    } else {
      _toolHandlers[toolCallName] = _ToolHandlerEntry(function);
    }
  }

  void removeToolCall(ToolName toolCallName) {
    final entry = _toolHandlers[toolCallName];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount <= 0) {
      _toolHandlers.remove(toolCallName);
    }
  }

  void addTools(ToolRegistry toolRegistry) {
    for (var MapEntry(:key, value: callback) in toolRegistry.tools.entries) {
      addToolCall(key, callback.execute);
    }
  }

  void removeTools(ToolRegistry toolRegistry) {
    for (final key in toolRegistry.tools.keys) {
      removeToolCall(key);
    }
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

/// A registered tool handler plus its live ownership count.
///
/// Ref-counting lets overlapping `generate` calls share a tool handler safely;
/// the handler is removed only when the last owner calls [FoundationApi.removeToolCall].
class _ToolHandlerEntry {
  _ToolHandlerEntry(this.callback);
  final ToolCallCallback callback;
  int refCount = 1;
}
