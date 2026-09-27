import 'package:test/test.dart';
import 'package:universal_automation_conformance/universal_automation_conformance.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_linux/universal_driver_linux.dart';
import 'package:universal_driver_linux/testing.dart';

void main() {
  late FakeAtspiBus bus;
  late AtspiDriver driver;

  setUp(() {
    bus = FakeAtspiBus();
    driver = AtspiDriver(bus);
  });

  test('maps the AT-SPI tree onto the family snapshot model', () async {
    final snapshot = await driver.snapshot();
    expect(snapshot.roots, hasLength(1));
    final root = snapshot.roots.first;
    expect(root.role, 'root');
    expect(root.byRole('button', name: 'Save'), isNotNull);
    expect(root.byRole('textbox', name: 'Email'), isNotNull);
  });

  test('clicks dispatch AT-SPI actions by name', () async {
    await driver.perform(ClickAction(name: 'Save'));
    expect(bus.invoked, ['${bus.rootRef.path}/1#0']);
  });

  test('refuses navigation loudly', () async {
    await expectLater(
      driver.perform(NavigateAction(Uri.parse('https://example.test'))),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('declares honest capabilities', () {
    expect(driver.capabilities.a11yTree, isTrue);
    expect(driver.capabilities.screenshot, isFalse);
    expect(driver.capabilities.evaluate, isFalse);
  });
}
