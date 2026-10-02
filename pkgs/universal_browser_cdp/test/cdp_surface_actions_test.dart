import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;
  late Uri httpBase;

  setUp(() async {
    server = FakeCdpServer();
    httpBase = await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('CdpDriver surface actions (window.__mcpActions)', () {
    test('lists the page-registered catalog', () async {
      server.evaluateHandler = (expression) => [
        {
          'name': 'checkout_flow',
          'description': 'Runs the checkout flow',
          'inputSchema': {
            'type': 'object',
            'required': ['sku'],
          },
        },
        {'name': 'reset_state'},
      ];
      final session = await CdpBrowserSession.attach(httpBase);
      final driver = CdpDriver(session.page);
      expect(driver, isA<AutomationActionCatalog>());
      final actions = await driver.actions();
      expect(actions, hasLength(2));
      expect(actions[0].name, 'checkout_flow');
      expect(actions[0].description, 'Runs the checkout flow');
      expect(actions[0].inputSchema?['required'], ['sku']);
      expect(actions[1].name, 'reset_state');
      expect(actions[1].inputSchema, isNull);
    });

    test('empty registry reads as universal-verbs-only', () async {
      server.evaluateHandler = (expression) => <Object?>[];
      final session = await CdpBrowserSession.attach(httpBase);
      final driver = CdpDriver(session.page);
      expect(await driver.actions(), isEmpty);
    });

    test('invoke dispatches by name with JSON-encoded args', () async {
      final expressions = <String>[];
      server.evaluateHandler = (expression) {
        expressions.add(expression);
        return const {'ok': true};
      };
      final session = await CdpBrowserSession.attach(httpBase);
      final driver = CdpDriver(session.page);
      await driver.perform(
        const InvokeAction('checkout_flow', args: {'sku': 'x-1', 'n': 2}),
      );
      final dispatched = expressions.last;
      expect(dispatched, contains('"checkout_flow"'));
      expect(dispatched, contains('"sku":"x-1"'));
      expect(dispatched, contains('"n":2'));
    });

    test('unknown action surfaces the JS rejection', () async {
      server.evaluateException = 'unknown surface action: nope';
      final session = await CdpBrowserSession.attach(httpBase);
      final driver = CdpDriver(session.page);
      await expectLater(
        driver.perform(const InvokeAction('nope')),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.message,
            'message',
            contains('unknown surface action: nope'),
          ),
        ),
      );
    });
  });
}
