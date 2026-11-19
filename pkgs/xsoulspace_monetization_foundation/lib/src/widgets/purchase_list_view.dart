import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'purchase_products_state.dart';

/// Signature for building the visual representation of a single product.
///
/// [onAction] is the view's action callback (buy or subscribe); attach it
/// to the interactive part of the returned widget.
typedef ProductItemBuilder = Widget Function(
  BuildContext context,
  PurchaseProductDetailsModel product,
  VoidCallback onAction,
);

/// Signature for building the visual representation of an error.
typedef ProductsErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
);

/// {@template purchase_list_view}
/// Material-free view that renders one-time purchasable products.
///
/// The view owns no visuals and no async logic: state flows in through
/// [state], purchase intent flows out through [onBuy], and every pixel is
/// drawn by caller-supplied builders. Produce the [PurchaseProductsState]
/// with your own state management (a `FutureBuilder`, a `ChangeNotifier`
/// resource, or anything else).
/// {@endtemplate}
class PurchaseListView extends StatelessWidget {
  /// {@macro purchase_list_view}
  const PurchaseListView({
    required this.state,
    required this.onBuy,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.itemBuilder,
    super.key,
  });

  /// Current state of the products fetch.
  final PurchaseProductsState state;

  /// Callback invoked when the user chooses to buy a product.
  final ValueChanged<PurchaseProductDetailsModel> onBuy;

  /// Builds the visual shown while [ProductsLoading].
  final WidgetBuilder loadingBuilder;

  /// Builds the visual shown for [ProductsError].
  final ProductsErrorBuilder errorBuilder;

  /// Builds the visual for each product while [ProductsReady].
  final ProductItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => switch (state) {
    ProductsLoading() => loadingBuilder(context),
    ProductsError(:final error) => errorBuilder(context, error),
    ProductsReady(:final products) => ListView.builder(
      itemCount: products.length,
      itemBuilder: (context, index) =>
          itemBuilder(context, products[index], () => onBuy(products[index])),
    ),
  };
}
