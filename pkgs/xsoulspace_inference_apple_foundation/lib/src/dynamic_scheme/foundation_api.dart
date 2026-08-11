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

  Future<bool> isAvailable() async {
    final result = await _channel.invokeMethod<bool>('isAvailable');
    return jsonDecodeBool(result);
  }

  Future<String> generate({required Map<String, dynamic> json}) async {
    final response = await _channel.invokeMethod<String>('generate', json);
    return jsonDecodeString(response);
  }
}
