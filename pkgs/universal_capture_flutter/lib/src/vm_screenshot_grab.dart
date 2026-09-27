import 'dart:convert';
import 'dart:typed_data';

import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vm_io;

/// Screenshot grabber over a Flutter app's Dart VM service.
///
/// Connects to a running (debug/profile) Flutter app, binds to the
/// isolate that registered the MCP toolkit, and serves PNG frames from
/// `ext.mcp.toolkit.view_screenshots` — the same extension the MCP
/// server uses. Feed [grab] into a [ToolkitFrameSource]:
///
/// ```dart
/// final grab = await VmScreenshotGrabber.connect(vmServiceUri);
/// final source = ToolkitFrameSource(grab: grab.grab);
/// ```
///
/// The grabber does not own the app process; closing it only releases
/// the VM-service connection.
final class VmScreenshotGrabber {
  VmScreenshotGrabber._(this._service, this._isolateId);

  final vm.VmService _service;
  final String _isolateId;

  /// Connects to a `ws://`/`http://` VM service URI and binds to the
  /// toolkit isolate.
  ///
  /// Throws [StateError] when the VM answers but no isolate carries the
  /// toolkit registration — the app must be run with
  /// `MCPToolkitBinding` (debug or profile mode).
  static Future<VmScreenshotGrabber> connect(final Uri vmServiceUri) async {
    final service = await vm_io.vmServiceConnectUri(
      normalizeWsUri(vmServiceUri).toString(),
    );
    final name = await service.getVM();
    for (final ref in [...?name.isolates]) {
      try {
        final isolate = await service.getIsolate(ref.id!);
        final extensions = List<String>.from(
          isolate.extensionRPCs ?? const <String>[],
        );
        if (extensions.any((name) => name.startsWith('ext.mcp.toolkit.'))) {
          return VmScreenshotGrabber._(service, ref.id!);
        }
      } on vm.RPCError {
        continue;
      }
    }
    throw StateError('no MCP toolkit isolate at $vmServiceUri');
  }

  /// Captures one PNG frame of the app's main view.
  Future<Uint8List> grab() async {
    final response = await _service.callServiceExtension(
      'ext.mcp.toolkit.view_screenshots',
      isolateId: _isolateId,
      args: <String, String>{'compress': 'false'},
    );
    final images = (response.json?['images'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList();
    if (images.isEmpty) {
      throw StateError('view_screenshots returned no images');
    }
    return base64Decode(images.first);
  }

  /// Releases the VM-service connection. Idempotent.
  Future<void> close() => _service.dispose();

  /// Normalizes `http(s)://…/#authToken=…` VM service announcements into
  /// the WS endpoint the vm_service client expects. `ws://`/`wss://`
  /// URIs pass through unchanged.
  static Uri normalizeWsUri(final Uri uri) {
    if (uri.scheme == 'ws' || uri.scheme == 'wss') return uri;
    final path = uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws';
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      fragment: null,
      path: path,
    );
  }
}
