import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

void main() {
  group('InvokeAction', () {
    test('carries a name and arguments', () {
      const action = InvokeAction('app.checkout_flow', args: {'sku': 'x-1'});
      expect(action.name, 'app.checkout_flow');
      expect(action.args, {'sku': 'x-1'});
      expect(action, isA<AutomationAction>());
      expect(action.toString(), 'InvokeAction(app.checkout_flow)');
    });

    test('args default to empty', () {
      const action = InvokeAction('reset_state');
      expect(action.args, isEmpty);
    });

    test('rejects empty names (const-constructor assert)', () {
      expect(() => InvokeAction(''), throwsA(isA<AssertionError>()));
    });
  });

  group('SurfaceActionDescriptor', () {
    test('round-trips through JSON', () {
      const descriptor = SurfaceActionDescriptor(
        name: 'checkout_flow',
        description: 'Runs the checkout flow',
        inputSchema: {
          'type': 'object',
          'required': ['sku'],
        },
      );
      final restored = SurfaceActionDescriptor.fromJson(descriptor.toJson());
      expect(restored, isNotNull);
      expect(restored!.name, descriptor.name);
      expect(restored.description, descriptor.description);
      expect(restored.inputSchema, descriptor.inputSchema);
    });

    test('schema is optional', () {
      const descriptor = SurfaceActionDescriptor(name: 'reset_state');
      final restored = SurfaceActionDescriptor.fromJson(descriptor.toJson());
      expect(restored!.inputSchema, isNull);
      expect(restored.description, isEmpty);
    });

    test('fromJson refuses malformed payloads', () {
      expect(SurfaceActionDescriptor.fromJson(null), isNull);
      expect(SurfaceActionDescriptor.fromJson('nope'), isNull);
      expect(SurfaceActionDescriptor.fromJson(const {}), isNull);
      expect(
        SurfaceActionDescriptor.fromJson({'name': ''}),
        isNull,
      );
    });
  });

  group('behavioral synthesis', () {
    test('refuses catalog actions — they carry their own dispatch', () {
      expect(
        () => synthesizeBehavior(
          BehaviorProfile.humanPrior(7),
          7,
          const InvokeAction('checkout_flow'),
        ),
        throwsA(
          isA<SpecViolationException>().having(
            (e) => e.violations.join(' '),
            'violations',
            contains('checkout_flow'),
          ),
        ),
      );
    });
  });
}
