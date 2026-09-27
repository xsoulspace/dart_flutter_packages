import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_windows/universal_driver_windows.dart';
import 'package:universal_driver_windows/testing.dart';

void main() {
  late FakeUiaSidecarTransport transport;
  late UiaSidecarClient client;
  late UiaDriver driver;

  setUp(() async {
    transport = FakeUiaSidecarTransport();
    client = UiaSidecarClient(transport);
    transport.serveHandshake();
    await client.handshake;
    driver = UiaDriver(client);
  });

  tearDown(() async {
    await client.close();
  });

  test('maps the UIA tree onto the family snapshot model', () async {
    final snapshot = await driver.snapshot();
    final root = snapshot.roots.single;
    expect(root.role, 'checkbox'); // controlType 50025 mapped
    expect(root.byRole('button', name: 'OK'), isNotNull);
  });

  test('clicks dispatch InvokePattern by name', () async {
    await driver.perform(ClickAction(name: 'OK'));
    final last = transport.written.last;
    expect(last, contains('"invoke"'));
    expect(last, contains('"OK"'));
  });

  test('refuses surfaces UIA does not have, loudly', () async {
    await expectLater(
      driver.perform(NavigateAction(Uri.parse('https://example.test'))),
      throwsA(isA<DriverUnsupportedException>()),
    );
    await expectLater(
      driver.perform(EvaluateAction('1+1')),
      throwsA(isA<DriverUnsupportedException>()),
    );
    await expectLater(driver.screenshot(),
        throwsA(isA<DriverUnsupportedException>()));
  });

  test('sidecar errors surface as UiaSidecarException', () async {
    transport.failNext = 'element has no InvokePattern';
    await expectLater(
      driver.perform(ClickAction(name: 'missing')),
      throwsA(isA<UiaSidecarException>()),
    );
  });

  test('close is idempotent', () async {
    await driver.close();
    await driver.close();
    expect(() => driver.snapshot(), throwsStateError);
  });
}
