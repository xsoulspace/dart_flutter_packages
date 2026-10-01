/// Pure-Dart Chrome DevTools Protocol (CDP) client.
///
/// Attach to a Chromium-based browser's debug endpoint and drive it: probe
/// readiness (`/json/version`, the oka borrowed-lease identity check),
/// enumerate targets (`/json/list`), then observe and act — accessibility
/// snapshots, intent-level actions, screenshots, screencast-ready frame
/// events.
///
/// The client takes an endpoint; it never launches a browser. Production
/// lifecycle (spawning, leases, profiles) belongs to oka's session targets;
/// this package consumes the `session-<name>-handle` they publish.
library;

export 'src/automation_exceptions_export.dart';
export 'src/cdp_behavior.dart';
export 'src/cdp_browser.dart';
export 'src/cdp_connection.dart';
export 'src/cdp_discovery.dart';
export 'src/cdp_driver.dart';
export 'src/cdp_network.dart';
export 'src/cdp_page.dart';
