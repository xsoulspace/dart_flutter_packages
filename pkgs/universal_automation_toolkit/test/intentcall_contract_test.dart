import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/compose.dart';

/// Layer 1 of the intentcall verification: the toolkit's parser against
/// intentcall's own serialization goldens (mirrored from
/// intentcall_core's `agent_automation_hint_test.dart` and
/// intentcall_mcp's `mcp_publish_adapter_test.dart` projection).
void main() {
  group('hint goldens (intentcall_core semantics)', () {
    test('round-trips through JSON including the action', () {
      final json = {
        'driver': 'toolkit',
        'action': 'type',
        'locator': {'css': 's_12'},
      };
      final hint = IntentHint.fromJson(json)!;
      expect(hint.verb, IntentVerb.type);
      expect(hint.locator, {'css': 's_12'});
      // intentcall's toJson output reparses identically.
      final restored = IntentHint.fromJson(hint.toJson())!;
      expect(restored, hint);
    });

    test('absent action means click (pre-action manifests)', () {
      final hint = IntentHint.fromJson({
        'driver': 'cdp',
        'locator': {'css': '#buy'},
      })!;
      expect(hint.verb, IntentVerb.click);
    });

    test('unknown action parses to null (refuse, never guess)', () {
      expect(
        IntentHint.fromJson({
          'driver': 'cdp',
          'action': 'explode',
          'locator': {'css': '#buy'},
        }),
        isNull,
      );
    });

    test('null-safe for absent or malformed input', () {
      expect(IntentHint.fromJson(null), isNull);
      expect(IntentHint.fromJson('toolkit'), isNull);
      expect(IntentHint.fromJson({'driver': 'toolkit'}), isNull);
      expect(
        IntentHint.fromJson({
          'driver': 'toolkit',
          'locator': {'name': 7},
        }),
        isNull,
      );
    });

    test('lowering matches the intentcall invocation contract', () {
      // click by accessible name:
      final click = IntentHint(
        driver: 'cdp',
        verb: IntentVerb.click,
        locator: {'name': 'Buy', 'role': 'button'},
      ).lowerToAction(label: 't');
      expect((click as ClickAction).name, 'Buy');
      expect(click.role, 'button');
      // type carries the text from the INVOCATION, not the registration:
      final type = IntentHint(
        driver: 'cdp',
        verb: IntentVerb.type,
        locator: {'css': 's_12'},
      ).lowerToAction(args: {'text': 'hi'}, label: 't') as TypeAction;
      expect(type.text, 'hi');
      expect(type.css, 's_12');
      // custom names the catalog action under locator.name:
      final custom = IntentHint(
        driver: 'cdp',
        verb: IntentVerb.custom,
        locator: {'name': 'checkout'},
      ).lowerToAction(args: {'sku': '1'}, label: 't') as InvokeAction;
      expect(custom.name, 'checkout');
      expect(custom.args, {'sku': '1'});
    });
  });

  group('mcp_publish_adapter projection goldens', () {
    // Mirrored from intentcall_mcp's mcp_publish_adapter_test.dart: a
    // descriptor `app.buy item` projects as tool `app_buy_item` with the
    // hint under _meta; hint-less tools stay meta-free.
    const capture = {
      'tools': [
        {
          'name': 'app_buy_item',
          'description': 'Buy an item from the cart',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'sku': {'type': 'string', 'description': 'stock keeping unit'},
              'quantity': {'type': 'integer'},
            },
            'required': ['sku'],
          },
          '_meta': {
            'dev.intentcall/automation': {
              'driver': 'toolkit',
              'action': 'click',
              'locator': {'name': 'Buy'},
            },
          },
        },
        {
          'name': 'fmt_plain_tool',
          'description': 'A tool without a hint stays meta-free',
          'inputSchema': {'type': 'object', 'properties': {}},
        },
      ],
    };

    test('fromMcpToolsList ingests the projected payload', () {
      final registry = IntentRegistry.fromMcpToolsList(capture, app: 'shop');
      final buyItem = registry.intent('shop', 'app_buy_item');
      expect(buyItem, isNotNull);
      expect(buyItem!.hint.driver, 'toolkit');
      expect(buyItem.hint.verb, IntentVerb.click);
      expect(buyItem.hint.locator, {'name': 'Buy'});
      // Plain tools are skipped, not failed.
      expect(registry.intent('shop', 'fmt_plain_tool'), isNull);
      // inputSchema.properties map onto declared parameters.
      final sku = buyItem.parameters
          .firstWhere((parameter) => parameter['name'] == 'sku');
      expect(sku['required'], true);
      expect(sku['type'], 'string');
      expect(
        buyItem.parameters
            .firstWhere((parameter) => parameter['name'] == 'quantity')
            .containsKey('required'),
        isFalse,
      );
      // ...and the intent validates eagerly in a plan.
      final plan = AutomationPlan(
        sessions: [cdp('browser', uri: Uri.parse('http://127.0.0.1:1'))],
        intents: registry,
        scenarios: [
          scenario('s', steps: [intent('shop', 'app_buy_item', args: {'sku': 'SKU-1'})]),
        ],
      );
      expect(plan.validate(), isEmpty);
    });

    test('fromMcpToolsList accepts a bare tool list and round-trips', () {
      final registry = IntentRegistry.fromMcpToolsList(
        capture['tools'],
        app: 'shop',
      );
      final document = registry.toJson();
      // The manifest form reparses through the file path.
      final file = File(
        '${Directory.systemTemp.path}/uat-intents-${DateTime.now().microsecondsSinceEpoch}.json',
      )..writeAsStringSync(jsonEncode(document));
      addTearDown(file.deleteSync);
      final reloaded = IntentRegistry.fromFiles([file.path]);
      expect(
        reloaded.intent('shop', 'app_buy_item')!.hint.toJson(),
        {
          'driver': 'toolkit',
          'action': 'click',
          'locator': {'name': 'Buy'},
        },
      );
    });

    test('ingests the REAL flutter_mcp_toolkit_server capture', () {
      final file = File('showcase/fmt-tools.capture.json');
      if (!file.existsSync()) {
        return; // capture shipped with the showcase; skip when absent
      }
      final payload = jsonDecode(file.readAsStringSync());
      final registry = IntentRegistry.fromMcpToolsList(payload, app: 'fmt');
      // The static fmt catalog carries no intentcall hints: every tool
      // is skipped, and the registry is simply empty (no crash — the
      // real payload parses end-to-end).
      expect(registry.manifests.single.intents, isEmpty);
    });

    test('duplicate tool names are violations', () {
      expect(
        () => IntentRegistry.fromMcpToolsList([
          {
            'name': 'app_x',
            '_meta': {
              'dev.intentcall/automation': {
                'driver': 'cdp',
                'action': 'click',
                'locator': {'name': 'X'},
              },
            },
          },
          {
            'name': 'app_x',
            '_meta': {
              'dev.intentcall/automation': {
                'driver': 'cdp',
                'action': 'click',
                'locator': {'name': 'X'},
              },
            },
          },
        ]),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
