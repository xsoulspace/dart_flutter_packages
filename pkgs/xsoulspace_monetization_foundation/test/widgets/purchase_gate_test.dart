import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';

PurchaseGate _gate({
  bool isLoading = false,
  Object? loadError,
  bool hasAccess = false,
  VoidCallback? onPurchase,
}) => PurchaseGate(
  isLoading: isLoading,
  loadError: loadError,
  hasAccess: hasAccess,
  onPurchase: onPurchase ?? () {},
  child: const Text('CONTENT'),
  loadingBuilder: (_) => const Text('LOADING'),
  errorBuilder: (_, e) => Text('ERROR: $e'),
  lockedBuilder: (_, action) =>
      TextButton(onPressed: action, child: const Text('UPGRADE')),
);

void main() {
  group('PurchaseGate', () {
    testWidgets('loadError precedes loading and access', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _gate(
            isLoading: true,
            hasAccess: true,
            loadError: StateError('check failed'),
          ),
        ),
      );

      expect(find.text('ERROR: Bad state: check failed'), findsOneWidget);
      expect(find.text('LOADING'), findsNothing);
      expect(find.text('CONTENT'), findsNothing);
    });

    testWidgets('isLoading precedes access', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _gate(isLoading: true, hasAccess: true)),
      );

      expect(find.text('LOADING'), findsOneWidget);
      expect(find.text('CONTENT'), findsNothing);
    });

    testWidgets('shows child when hasAccess', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _gate(hasAccess: true)));

      expect(find.text('CONTENT'), findsOneWidget);
      expect(find.text('UPGRADE'), findsNothing);
    });

    testWidgets('routes onPurchase through lockedBuilder', (tester) async {
      var purchaseCalls = 0;
      await tester.pumpWidget(
        MaterialApp(home: _gate(onPurchase: () => purchaseCalls++)),
      );

      expect(find.text('UPGRADE'), findsOneWidget);
      expect(find.text('CONTENT'), findsNothing);

      await tester.tap(find.text('UPGRADE'));
      expect(purchaseCalls, 1);
    });
  });
}
