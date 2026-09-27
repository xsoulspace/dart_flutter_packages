# universal_capture_flutter

Frame source over a **running Flutter app**: paced PNG frames from the
MCP toolkit's `ext.mcp.toolkit.view_screenshots` service extension,
polled through the Dart VM service and delivered through the
`universal_screencast` pipeline contracts.

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md),
capture split in [ADR 0038](../../docs/decisions/0038_automation_kernel_unification.md)).
This is the instrumented tier's observation plane: the app opts in by
binding [mcp_toolkit](https://pub.dev/packages/mcp_toolkit), and this
package turns it into a frame source that composes with every sink
(MJPEG, WebSocket, file recorder) the pipeline already has.

## What it does

- `ToolkitFrameSource(grab: …)` — a `FrameSource` that polls a grab
  function (pacing + single-flight at the source, PNG content type,
  `toolkit-flutter` source id). Pass any `Future<Uint8List>
  Function()`; frames are read-only (`frames != semantics` — for the
  semantic tree use an `AutomationDriver` snapshot).
- `VmScreenshotGrabber.connect(vmServiceUri)` — the out-of-the-box
  grab: connects to a `flutter run`/debug binary's VM service, binds to
  the isolate carrying the toolkit registration, and grabs PNG frames.
  `VmScreenshotGrabber.normalizeWsUri` converts `http://…/#authToken=…`
  run announcements into the `ws://…/ws` endpoint the VM client needs.

## Composition

```dart
import 'package:universal_capture_flutter/universal_capture_flutter.dart';
import 'package:universal_screencast/universal_screencast.dart';

final grab = await VmScreenshotGrabber.connect(vmServiceUri);
final pipeline = ScreencastPipeline.start(
  ScreencastComposition(
    source: ToolkitFrameSource(grab: grab.grab),
    sinks: [FileRecorderSink(directory)],
  ),
);
```

Audience policies and composition validation are the pipeline's job
(`universal_screencast`); this package only keeps the source honest.

## Requirements

- The Flutter app must run in debug or profile mode and bind
  `MCPToolkitBinding` (the `mcp_toolkit` package registers the
  extensions used here).
- Pure Dart on the driving side — no Flutter plugin surface.

## Non-claims

- Screenshot polling is paced capture, not a compositor-grade stream;
  for Chromium targets prefer `CdpScreencastFrameSource` (push-based,
  ack-aware), and for the OS-native tier `universal_capture_macos`.
- Frames never carry semantics and never mutate app state.
