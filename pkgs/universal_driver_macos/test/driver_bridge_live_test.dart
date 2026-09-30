import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

/// Live smoke tests against the real macOS accessibility tree.
///
/// Permission-gated and skipped by default: they need the Accessibility
/// grant for this process (and a focused application on screen). Run with:
/// `XS_AX_DRIVER_LIVE=1 dart test test/driver_bridge_live_test.dart`
void main() {
  final live = Platform.environment['XS_AX_DRIVER_LIVE'] == '1';
  if (!live) {
    return;
  }

  final driver = MacosDriver();

  test('bridge reports its version', () {
    expect(driver.bridge.version(), 'xs-ax-driver/1');
  });

  test('snapshot of the focused application yields semantic nodes', () async {
    if (!driver.axTrusted) {
      // Never prompts here: grant Accessibility for the test runner in
      // System Settings, then re-run this file.
      // ignore: avoid_print
      print(
        'SKIP: this process is not Accessibility-trusted yet; '
        'grant it in System Settings and re-run.',
      );
      return;
    }
    final snapshot = await driver.snapshot();
    expect(snapshot.roots, isNotEmpty);
    // ignore: avoid_print
    print(
      'snapshot: ${snapshot.nodes.length} nodes, '
      'root=${snapshot.roots.first.role}/${snapshot.roots.first.name}',
    );

    // The hover query at the window center resolves some element.
    final bounds = snapshot.roots.first.bounds;
    if (bounds != null) {
      final node = await driver.elementAtPosition(
        bounds.left + bounds.width / 2,
        bounds.top + bounds.height / 2,
      );
      // ignore: avoid_print
      print('elementAtPosition(center) = ${node.role}/${node.name}');
    }
  }, timeout: const Timeout(Duration(seconds: 15)));
}
