import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'purchase_list_view.dart';
import 'purchase_products_state.dart';

/// {@template subscription_list_view}
/// Material-free view that renders subscription offers.
///
/// The view owns no visuals and no async logic: state flows in through
/// [state], subscribe intent flows out through [onSubscribe], and every
/// pixel is drawn by caller-supplied builders. Success or failure feedback
/// (snackbars, dialogs, ...) is the caller's concern — the view never
/// touches the context after an action.
/// {@endtemplate}
class SubscriptionListView extends StatelessWidget {
  /// {@macro subscription_list_view}
  const SubscriptionListView({
    required this.state,
    required this.onSubscribe,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.itemBuilder,
    super.key,
  });

  /// Current state of the subscriptions fetch.
  final PurchaseProductsState state;

  /// Callback invoked when the user chooses to subscribe to a product.
  final ValueChanged<PurchaseProductDetailsModel> onSubscribe;

  /// Builds the visual shown while [ProductsLoading].
  final WidgetBuilder loadingBuilder;

  /// Builds the visual shown for [ProductsError].
  final ProductsErrorBuilder errorBuilder;

  /// Builds the visual for each subscription while [ProductsReady].
  final ProductItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => switch (state) {
    ProductsLoading() => loadingBuilder(context),
    ProductsError(:final error) => errorBuilder(context, error),
    ProductsReady(:final products) => ListView.builder(
      itemCount: products.length,
      itemBuilder: (context, index) => itemBuilder(
        context,
        products[index],
        () => onSubscribe(products[index]),
      ),
    ),
  };
}
