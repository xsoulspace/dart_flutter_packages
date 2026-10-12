import 'package:test/test.dart';
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
    expect(driver.capabilities.semanticWrite, isTrue);
  });

  test('setValue writes text fields through EditableText', () async {
    final writableBus = FakeAtspiBus(
      nodes: {
        '/org/a11y/atspi/accessible/root': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root',
          name: 'app window',
          role: 'frame',
        ),
        '/org/a11y/atspi/accessible/root/2': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root/2',
          name: 'Email',
          role: 'text',
          editableText: true,
        ),
      },
    );
    final writableDriver = AtspiDriver(writableBus);

    await writableDriver.perform(
      SetValueAction('me@example.test', name: 'Email'),
    );

    expect(writableBus.contentsWrites, [
      ('/org/a11y/atspi/accessible/root/2', 'me@example.test'),
    ]);
    expect(writableBus.valueWrites, isEmpty);
  });

  test('setValue ladders to the numeric Value interface when there is no '
      'EditableText', () async {
    final sliderBus = FakeAtspiBus(
      nodes: {
        '/org/a11y/atspi/accessible/root': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root',
          name: 'app window',
          role: 'frame',
        ),
        '/org/a11y/atspi/accessible/root/2': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root/2',
          name: 'Opacity',
          role: 'slider',
          value: 0.5,
        ),
      },
    );
    final sliderDriver = AtspiDriver(sliderBus);

    await sliderDriver.perform(SetValueAction('0.75', name: 'Opacity'));

    expect(sliderBus.contentsWrites, isEmpty);
    expect(sliderBus.valueWrites, [
      ('/org/a11y/atspi/accessible/root/2', 0.75),
    ]);
  });

  test('setValue refuses loudly when neither write interface exists and '
      'the value is not numeric', () async {
    await expectLater(
      driver.perform(SetValueAction('not numeric', name: 'Email')),
      throwsA(
        isA<DriverUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('no EditableText'),
        ),
      ),
    );
    expect(bus.contentsWrites, isEmpty);
    expect(bus.valueWrites, isEmpty);
  });

  test(
    'setValue refuses when the numeric value is refused by the peer',
    () async {
      await expectLater(
        driver.perform(SetValueAction('42', name: 'Email')),
        throwsA(
          isA<DriverUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('neither EditableText nor Value'),
          ),
        ),
      );
    },
  );

  test('elementAction resolves the advertised name to its index', () async {
    final menuBus = FakeAtspiBus(
      nodes: {
        '/org/a11y/atspi/accessible/root': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root',
          name: 'app window',
          role: 'frame',
        ),
        '/org/a11y/atspi/accessible/root/1': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root/1',
          name: 'Save',
          role: 'push button',
          actionNames: ['press', 'menu'],
        ),
      },
    );
    final menuDriver = AtspiDriver(menuBus);

    await menuDriver.perform(ElementAction('menu', name: 'Save'));

    expect(menuBus.invoked, ['/org/a11y/atspi/accessible/root/1#1']);
  });

  test('elementAction matches advertised names case-insensitively and '
      'names the advertised set on a miss', () async {
    final confirmBus = FakeAtspiBus(
      nodes: {
        '/org/a11y/atspi/accessible/root': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root',
          name: 'app window',
          role: 'frame',
        ),
        '/org/a11y/atspi/accessible/root/1': FakeAtspiNode(
          path: '/org/a11y/atspi/accessible/root/1',
          name: 'Save',
          role: 'push button',
          actionNames: ['AXConfirm'],
        ),
      },
    );
    final confirmDriver = AtspiDriver(confirmBus);

    await confirmDriver.perform(ElementAction('axconfirm', name: 'Save'));
    expect(confirmBus.invoked, ['/org/a11y/atspi/accessible/root/1#0']);

    await expectLater(
      confirmDriver.perform(ElementAction('AXZoom', name: 'Save')),
      throwsA(
        isA<ProtocolException>().having(
          (error) => error.message,
          'message',
          allOf(contains('AXZoom'), contains('AXConfirm')),
        ),
      ),
    );
  });
}
