import 'package:flutter/material.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template subscription_screen}
/// A widget that displays available subscriptions and allows
/// users to subscribe.
/// {@endtemplate}
class SubscriptionScreen extends StatelessWidget {
  /// {@macro subscription_screen}
  const SubscriptionScreen({
    required this.purchaseProvider,
    required this.productIds,
    super.key,
  });

  /// The purchase provider to handle subscription operations.
  final PurchaseProvider purchaseProvider;
  final List<PurchaseProductId> productIds;
  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Subscription Options')),
    body: FutureBuilder<List<PurchaseProductDetailsModel>>(
      // ignore: discarded_futures
      future: purchaseProvider.getSubscriptions(productIds),
      builder: (final context, final snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final subscriptions = snapshot.data ?? [];
        return ListView.builder(
          itemCount: subscriptions.length,
          itemBuilder: (final context, final index) {
            final subscription = subscriptions[index];
            return ListTile(
              title: Text(subscription.name),
              subtitle: Text(
                '${subscription.price} ${subscription.currency} / ${subscription.duration.inDays} days',
              ),
              trailing: ElevatedButton(
                onPressed: () async {
                  final result = await purchaseProvider.subscribe(subscription);
                  switch (result.type) {
                    case ResultType.success:
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Subscription successful!'),
                        ),
                      );
                    case ResultType.failure:
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Subscription failed: ${result.error}'),
                        ),
                      );
                  }
                },
                child: const Text('Subscribe'),
              ),
            );
          },
        );
      },
    ),
  );
}
