import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'driver_bindings.dart';

@Native<Int32 Function(Int32, Pointer<Pointer<Utf8>>)>(
  symbol: 'xs_axdrv_request_accessibility_json',
  assetId: 'package:universal_driver_macos/xs_ax_driver',
)
external int _request(int pid, Pointer<Pointer<Utf8>> output);

/// Request native accessibility from one running app without taking focus.
/// This is an explicit assistive-client request, not a read-only observation.
/// Attribute refusal codes are retained; success is verified by a fresh tree.
Map<String, dynamic> requestAppAccessibility(int pid) {
  if (pid <= 0) throw ArgumentError.value(pid, 'pid');
  final output = calloc<Pointer<Utf8>>();
  try {
    final code = _request(pid, output);
    if (code != 0) {
      throw ProtocolException('accessibility request failed', code: code);
    }
    return jsonDecode(output.value.toDartString()) as Map<String, dynamic>;
  } finally {
    if (output.value != nullptr) axdrvFree(output.value.cast());
    calloc.free(output);
  }
}
