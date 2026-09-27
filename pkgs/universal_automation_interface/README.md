# universal_automation_interface

Pure-Dart contracts for the universal automation family: endpoints,
session handles, drivers, actions, snapshots, fail-closed specs, and
structured events. **No Flutter, no protocol clients.**

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)):

- `universal_browser_cdp` — Chrome DevTools Protocol client.
- `universal_browser_webdriver` — W3C WebDriver client (Safari via
  `safaridriver`).
- `universal_screencast` — declarative frame pipeline.
- `universal_automation_conformance` — swappability suites.

## What this package fixes

- One vocabulary for the observe/act/verify loop across protocols
  (`AutomationDriver`, `AutomationAction`, `Snapshot`).
- Session-handle naming shared with oka (`session-<name>-handle`), so
  handles published by oka's session targets are consumed verbatim.
- Fail-closed composition types (`TypedSpec`, `SessionDescriptor`):
  invariants are validated before anything runs.
- Structured, payload-free events agents can classify
  (`FrameDelivered`, `SinkDegraded`, `PipelineFailed`).
- Ownership vocabulary (`StartMode`, `LeaseOwnership`) mirroring oka's
  process leases — borrowed sessions are reported, never stopped.

## Usage

```dart
import 'package:universal_automation_interface/universal_automation_interface.dart';

final endpoint = AutomationEndpoint(
  transport: AutomationTransport.cdp,
  uri: Uri.parse('http://127.0.0.1:9222'),
);

// oka-published handle for the same session:
final handle = SessionHandles.handle('chrome'); // session-chrome-handle
final cdpPort = SessionHandles.sub('chrome', 'cdp-port');
```

## Non-claims

- This package performs no I/O and attaches to nothing.
- It is not the oka lifecycle layer and never spawns or stops processes.
