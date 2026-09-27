import 'dart:async';
import 'dart:typed_data';

import 'package:universal_screencast/universal_screencast.dart';

import 'vm_screenshot_grab.dart';

/// [FrameSource] over a running Flutter app's MCP toolkit screenshots.
///
/// The instrumented counterpart of [CdpScreencastFrameSource]: instead of
/// Chromium's screencast domain, frames come from
/// `ext.mcp.toolkit.view_screenshots` — the same service extension the
/// MCP server's `get_screenshots` tool uses — polled through the Dart VM
/// service.
///
/// Pacing and single-flight live at the source ([PollingFrameSource]
/// discipline): a slow screenshot simply skips ticks. Frames are PNG
/// (`compress: false` on the wire) and read-only — `frames != semantics`;
/// for the semantic tree use an `AutomationDriver` snapshot.
///
/// ```dart
/// final grab = await VmScreenshotGrabber.connect(vmServiceUri);
/// final pipeline = ScreencastPipeline(
///   ScreencastComposition.validate(
///     source: ToolkitFrameSource(grab: grab.grab),
///     sinks: [FileRecorderSink(directory)],
///   ),
/// );
/// await pipeline.run();
/// ```
final class ToolkitFrameSource implements FrameSource {
  /// Creates a source polling [grab] every [interval].
  ToolkitFrameSource({
    required Future<Uint8List> Function() grab,
    Duration interval = const Duration(milliseconds: 250),
  }) : _delegate = PollingFrameSource(
         grab,
         interval: interval,
         contentType: 'image/png',
       );

  static const String _id = 'toolkit-flutter';

  final PollingFrameSource _delegate;

  @override
  String get id => _id;

  @override
  SourceCapabilities get capabilities => _delegate.capabilities;

  @override
  Stream<Frame> start() => _delegate.start().map(
    (frame) => Frame(
      sourceId: _id,
      sequence: frame.sequence,
      revision: frame.revision,
      bytes: frame.bytes,
      contentType: frame.contentType,
      capturedAt: frame.capturedAt,
    ),
  );

  @override
  Future<void> stop() => _delegate.stop();
}
