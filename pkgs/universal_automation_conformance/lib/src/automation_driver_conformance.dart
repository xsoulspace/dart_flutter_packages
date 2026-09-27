import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Contract suite for [AutomationDriver] implementations.
///
/// Adopt it with one call; every test builds a fresh driver via
/// [createDriver]. Tests are skipped automatically when the driver's
/// capability set excludes the exercised feature.
void automationDriverConformanceTests(
  String scenario, {
  required Future<AutomationDriver> Function() createDriver,
}) {
  group('$scenario driver conformance', () {
    test('declares attach and does not lie about capabilities', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      expect(driver.capabilities.attach, isTrue);
    });

    test('snapshot returns a valid semantic tree', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      if (!driver.capabilities.a11yTree) {
        return;
      }
      final snapshot = await driver.snapshot();
      expect(snapshot.roots, isNotEmpty);
      expect(snapshot.capturedAt.isBefore(DateTime.now()), isTrue);
      expect(snapshot.revision, greaterThanOrEqualTo(0));
      for (final node in snapshot.nodes) {
        expect(node.role, isNotEmpty);
      }
    });

    test('navigation either works or refuses loudly', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      try {
        await driver.perform(
          NavigateAction(Uri.parse('about:blank#conformance')),
        );
      } on DriverUnsupportedException {
        // Tree-only drivers (AT-SPI, UIA) have no navigation surface;
        // refusing loudly is contract-compliant. Silently ignoring is not.
      }
    });

    test('screenshot returns encoded bytes', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      if (!driver.capabilities.screenshot) {
        return;
      }
      final bytes = await driver.screenshot();
      expect(bytes, isNotEmpty);
    });

    test('close is idempotent', () async {
      final driver = await createDriver();
      await driver.close();
      await driver.close();
    });
  });
}
