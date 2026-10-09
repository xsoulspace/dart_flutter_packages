import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_webdriver/testing.dart';
import 'package:universal_browser_webdriver/universal_browser_webdriver.dart';

/// The ADR 0053 coordinate verbs over the W3C WebDriver tier: every verb
/// lowers to one pointer-action bundle in viewport coordinates.
void main() {
  late FakeWebDriverServer server;
  late WebDriverClient client;
  late WebDriverDriver driver;

  setUp(() async {
    server = FakeWebDriverServer();
    final base = await server.start();
    client = WebDriverClient(base);
    await client.newSession();
    driver = WebDriverDriver(client);
  });

  tearDown(() async {
    await client.deleteSession();
    await server.stop();
  });

  test('the driver advertises pointerCoordinates', () {
    expect(driver.capabilities.pointerCoordinates, isTrue);
  });

  test('clickAt lowers to move + down + up at the viewport point', () async {
    await driver.perform(const ClickAtAction(120, 80));
    expect(server.pointerActions.map((action) => action['type']).toList(), [
      'pointerMove',
      'pointerDown',
      'pointerUp',
    ]);
    expect(server.pointerActions[0]['x'], 120);
    expect(server.pointerActions[0]['y'], 80);
    expect(server.pointerActions[0]['origin'], 'viewport');
    expect(server.pointerActions[1]['button'], 0);
  });

  test('double clickAt emits two adjacent press pairs', () async {
    await driver.perform(const ClickAtAction(30, 40, clickCount: 2));
    final downs = server.pointerActions
        .where((action) => action['type'] == 'pointerDown')
        .toList();
    expect(downs, hasLength(2));
  });

  test('button names map to W3C codes', () async {
    await driver.perform(const ClickAtAction(1, 2, button: 'right'));
    await driver.perform(const ClickAtAction(3, 4, button: 'middle'));
    expect(
      server.pointerActions
          .where((action) => action['type'] == 'pointerDown')
          .map((action) => action['button'])
          .toList(),
      [2, 1],
    );
  });

  test('moveTo is a single viewport move', () async {
    await driver.perform(const MoveAction(30, 40));
    expect(server.pointerActions, [
      {
        'type': 'pointerMove',
        'duration': 0,
        'x': 30,
        'y': 40,
        'origin': 'viewport',
      },
    ]);
  });

  test('drag presses at the from-point and releases at the to-point',
      () async {
    await driver.perform(const DragAction(10, 20, 300, 400));
    expect(server.pointerActions.map((action) => action['type']).toList(), [
      'pointerMove',
      'pointerDown',
      'pointerMove',
      'pointerUp',
    ]);
    expect(server.pointerActions[0]['x'], 10);
    expect(server.pointerActions[0]['y'], 20);
    expect(server.pointerActions[2]['x'], 300);
    expect(server.pointerActions[2]['y'], 400);
  });

  test('shift+click is a keyboard source holding the chord', () async {
    await driver.perform(const ClickAtAction(1, 2, modifiers: ['shift']));
    // The pointer actions are unchanged; the keyboard source carries
    // the chord with pauses aligning the release past the pointer's.
    expect(server.pointerActions.map((action) => action['type']).toList(), [
      'pointerMove',
      'pointerDown',
      'pointerUp',
    ]);
    expect(server.keyPresses, ['\uE008']);
  });

  test('meta+drag releases the chord after the pointer does', () async {
    await driver.perform(
      const DragAction(0, 0, 40, 40, modifiers: ['meta']),
    );
    // keyDown Meta dispatched once; the keyUp lands in a later tick
    // (recorded after all pointer actions).
    expect(server.keyPresses, ['\uE03D']);
    expect(server.pointerActions.last['type'], 'pointerUp');
  });
}
