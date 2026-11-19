import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';

void main() {
  group('SubscriptionListView', () {
    testWidgets('renders errorBuilder on ProductsError', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionListView(
            state: const ProductsError('fetch failed'),
            onSubscribe: (_) {},
            loadingBuilder: (_) => const Text('LOADING'),
            errorBuilder: (_, e) => Text('ERROR: $e'),
            itemBuilder: (_, _, _) => const Text('ITEM'),
          ),
        ),
      );

      expect(find.text('ERROR: fetch failed'), findsOneWidget);
      expect(find.text('ITEM'), findsNothing);
    });

    testWidgets('renders itemBuilder per subscription and routes onSubscribe', (
      tester,
    ) async {
      final subscriptions = [
        aProduct(name: 'monthly'),
        aProduct(id: PurchaseProductId.fromJson('yearly'), name: 'yearly'),
      ];
      PurchaseProductDetailsModel? subscribed;
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionListView(
            state: ProductsReady(subscriptions),
            onSubscribe: (product) => subscribed = product,
            loadingBuilder: (_) => const Text('LOADING'),
            errorBuilder: (_, _) => const Text('ERROR'),
            itemBuilder: (_, product, onAction) =>
                TextButton(onPressed: onAction, child: Text(product.name)),
          ),
        ),
      );

      expect(find.text('monthly'), findsOneWidget);
      expect(find.text('yearly'), findsOneWidget);

      await tester.tap(find.text('yearly'));
      expect(subscribed?.productId, subscriptions[1].productId);
    });

    testWidgets('renders loadingBuilder while ProductsLoading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionListView(
            state: const ProductsLoading(),
            onSubscribe: (_) {},
            loadingBuilder: (_) => const Text('LOADING'),
            errorBuilder: (_, _) => const Text('ERROR'),
            itemBuilder: (_, _, _) => const Text('ITEM'),
          ),
        ),
      );

      expect(find.text('LOADING'), findsOneWidget);
    });
  });
}
