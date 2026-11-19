import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';

void main() {
  group('PurchaseListView', () {
    testWidgets('renders loadingBuilder while ProductsLoading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseListView(
            state: const ProductsLoading(),
            onBuy: (_) {},
            loadingBuilder: (_) => const Text('LOADING'),
            errorBuilder: (_, _) => const Text('ERROR'),
            itemBuilder: (_, _, _) => const Text('ITEM'),
          ),
        ),
      );

      expect(find.text('LOADING'), findsOneWidget);
      expect(find.text('ITEM'), findsNothing);
    });

    testWidgets('passes the error object to errorBuilder', (tester) async {
      final error = StateError('boom');
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseListView(
            state: ProductsError(error),
            onBuy: (_) {},
            loadingBuilder: (_) => const Text('LOADING'),
            errorBuilder: (_, e) => Text('ERROR: $e'),
            itemBuilder: (_, _, _) => const Text('ITEM'),
          ),
        ),
      );

      expect(find.text('ERROR: Bad state: boom'), findsOneWidget);
    });

    testWidgets('renders itemBuilder per product and routes onBuy', (
      tester,
    ) async {
      final products = [
        aProduct(name: 'one', type: PurchaseProductType.nonConsumable),
        aProduct(
          id: PurchaseProductId.fromJson('two'),
          name: 'two',
          type: PurchaseProductType.nonConsumable,
        ),
      ];
      PurchaseProductDetailsModel? bought;
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseListView(
            state: ProductsReady(products),
            onBuy: (product) => bought = product,
            loadingBuilder: (_) => const Text('LOADING'),
            errorBuilder: (_, _) => const Text('ERROR'),
            itemBuilder: (_, product, onAction) =>
                TextButton(onPressed: onAction, child: Text(product.name)),
          ),
        ),
      );

      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);

      await tester.tap(find.text('two'));
      expect(bought?.productId, products[1].productId);
      expect(bought?.productId, isNot(products[0].productId));
    });
  });
}
