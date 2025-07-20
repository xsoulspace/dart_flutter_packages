import 'package:flutter/material.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template purchase_screen}
/// A widget that displays available one-time purchases and allows users
/// to buy them.
/// {@endtemplate}
class PurchaseScreen extends StatelessWidget {
  /// {@macro purchase_screen}
  const PurchaseScreen({
    required this.purchaseProvider,
    required this.productIds,
    super.key,
  });

  /// The purchase provider to handle purchase operations.
  final PurchaseProvider purchaseProvider;
  final List<PurchaseProductId> productIds;

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchase Options')),
    body: FutureBuilder<List<PurchaseProductDetailsModel>>(
      // ignore: discarded_futures
      future: purchaseProvider.getNonConsumables(productIds),
      builder: (final context, final snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final purchases = snapshot.data ?? [];
        return ListView.builder(
          itemCount: purchases.length,
          itemBuilder: (final context, final index) {
            final purchase = purchases[index];
            return ListTile(
              title: Text(purchase.name),
              subtitle: Text('${purchase.price} ${purchase.currency}'),
              trailing: ElevatedButton(
                onPressed: () async {
                  await purchaseProvider.purchaseNonConsumable(purchase);
                },
                child: const Text('Buy'),
              ),
            );
          },
        );
      },
    ),
  );
}
